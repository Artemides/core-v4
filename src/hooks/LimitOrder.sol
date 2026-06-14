// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {PoolKey} from "./../types/PoolKey.sol";
import {TStore} from "./TStore.sol";
import {SwapParams, ModifyLiquidityParams} from "./../types/PoolOperation.sol";
import {BalanceDelta} from "./../types/BalanceDelta.sol";
import {IPoolManager} from "./../interfaces/IPoolManager.sol";
import {Hooks} from "./../libraries/Hooks.sol";
import {PoolId} from "./../types/PoolId.sol";
import {IHooks} from "./../interfaces/IHooks.sol";
import {Currency} from "./../types/Currency.sol";
import {StateLibrary} from "./../libraries/StateLibrary.sol";
import {SafeCast} from "./../libraries/SafeCast.sol";
import {IUnlockCallback} from "./../interfaces/callback/IUnlockCallback.sol";
import {IERC20Minimal} from "./../interfaces/external/IERC20Minimal.sol";
import {FullMath} from "./../libraries/FullMath.sol";

abstract contract LimitOrderHook is TStore, IUnlockCallback {
    using SafeCast for int128;

    uint256 constant ADD_LIQUIDITY = 1;
    uint256 constant REMOVE_LIQUIDITY = 2;

    struct Bucket {
        bool fulfilled;
        uint256 amount0;
        uint256 amount1;
        uint128 liquidity;
        mapping(address user => uint128 amount) sizes;
    }

    IPoolManager poolManager;

    mapping(bytes32 bucketId => uint256 index) public slots;
    mapping(bytes32 bucketId => mapping(uint256 index => Bucket)) public buckets;
    mapping(PoolId => int24 tick) public ticks;

    event Place(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    event Cancel(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint128 liquidity
    );

    event Take(
        bytes32 indexed poolId,
        uint256 indexed slot,
        address indexed user,
        int24 tickLower,
        bool zeroForOne,
        uint256 amount0,
        uint256 amount1
    );

    error NotPoolManager();
    error InvalidTick();
    error BucketFulfilled(bytes32 bucketId);
    error InsufficientLiquidity();

    modifier OnlyPoolManafer() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
        Hooks.validateHookPermissions(IHooks(address(this)), getHookPermissions());
    }

    /// @notice IHooks
    function afterInitialize(address sender, PoolKey calldata key, uint160 sqrtPriceX96, int24 tick)
        external
        returns (bytes4)
    {
        ticks[key.toId()] = tick;

        return this.afterInitialize.selector;
    }

    function place(PoolKey memory poolKey, int24 tickLower, bool zeroForOne, uint128 liquidity)
        external
        payable
        setAction(ADD_LIQUIDITY)
    {
        if (tickLower % poolKey.tickSpacing != 0) revert InvalidTick();
        if (tickLower == _getTick(poolKey.toId())) revert InvalidTick();

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower,
            tickUpper: tickLower + poolKey.tickSpacing,
            liquidityDelta: int128(liquidity),
            salt: ""
        });

        PoolId id = poolKey.toId();

        bytes memory data = abi.encode(msg.sender, poolKey, params);
        poolManager.unlock(data);

        bytes32 bucketId = getBucketId(id, tickLower, zeroForOne);
        uint256 currentSlot = slots[bucketId];

        Bucket storage bucket = buckets[bucketId][currentSlot];

        bucket.sizes[msg.sender] = liquidity;
        bucket.liquidity += liquidity;

        int24 initialized = ticks[id];
        if (initialized == 0) {
            ticks[id] = tickLower;
        }

        emit Place(PoolId.unwrap(id), currentSlot, msg.sender, tickLower, zeroForOne, liquidity);
    }

    function cancel(PoolKey calldata key, int24 tickLower, bool zeroForOne) external setAction(REMOVE_LIQUIDITY) {
        PoolId poolId = key.toId();
        bytes32 bucketId = getBucketId(poolId, tickLower, zeroForOne);

        uint256 slot = slots[bucketId];
        Bucket storage bucket = buckets[bucketId][slot];
        if (bucket.fulfilled) revert BucketFulfilled(bucketId);

        uint128 liquidity = bucket.sizes[msg.sender];
        if (liquidity == 0) revert InsufficientLiquidity();

        ModifyLiquidityParams memory params = ModifyLiquidityParams({
            tickLower: tickLower, tickUpper: tickLower + key.tickSpacing, liquidityDelta: int128(liquidity), salt: ""
        });

        bytes memory data = abi.encode(msg.sender, key, params);
        data = poolManager.unlock(data);

        bucket.liquidity -= liquidity;
        bucket.sizes[msg.sender] -= liquidity;

        (, BalanceDelta deltaFees) = abi.decode(data, (BalanceDelta, BalanceDelta));
        int128 fees0 = deltaFees.amount0();
        int128 fees1 = deltaFees.amount1();

        if (fees0 > 0) bucket.amount0 += fees0.toUint256();
        if (fees1 > 0) bucket.amount1 += fees1.toUint256();

        if (bucket.liquidity == 0) {
            //return fees to the last caller?
        }

        emit Cancel(PoolId.unwrap(poolId), slot, msg.sender, tickLower, zeroForOne, liquidity);
    }

    function take(PoolKey calldata key, int24 tickLower, bool zeroForOne, uint256 slot) external {
        PoolId id = key.toId();
        bytes32 bucketId = getBucketId(id, tickLower, zeroForOne);

        (bool fulfilled, uint256 amount0, uint256 amount1, uint128 liquidity) = getBucket(bucketId, slot);
        if (fulfilled) revert BucketFulfilled(bucketId);

        uint128 liquidityShare = getOrderSize(bucketId, slot, msg.sender);
        if (liquidityShare == 0) revert InsufficientLiquidity();

        uint256 amount0Owed;

        if (amount0 > 0) {
            amount0Owed = FullMath.mulDiv(amount0, liquidityShare, liquidity);
        }

        uint256 amount1Owed;
        if (amount1 > 0) {
            amount1Owed = FullMath.mulDiv(amount1, liquidityShare, liquidity);
        }

        delete buckets[bucketId][slot].sizes[msg.sender];

        if (amount0Owed > 0) key.currency0.transfer(msg.sender, amount0Owed);
        if (amount1Owed > 0) key.currency0.transfer(msg.sender, amount1Owed);

        emit Take(PoolId.unwrap(id), slot, msg.sender, tickLower, zeroForOne, amount0, amount1);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (address owner, PoolKey memory poolKey, ModifyLiquidityParams memory params) =
            abi.decode(data, (address, PoolKey, ModifyLiquidityParams));

        (BalanceDelta delta, BalanceDelta feesDelta) = poolManager.modifyLiquidity(poolKey, params, "");

        (int128 amount0, int128 amount1) = (delta.amount0(), delta.amount1());

        _takeOrSetlle(poolKey.currency0, amount0, owner);
        _takeOrSetlle(poolKey.currency1, amount1, owner);

        return abi.encode(delta, feesDelta);
    }

    function _takeOrSetlle(Currency currency, int128 amount, address owner) internal {
        if (amount > 0) {
            poolManager.take(currency, owner, amount.toUint256());
        } else {
            poolManager.sync(currency);
            uint256 amountIn = (-amount).toUint256();

            if (currency.isAddressZero()) {
                poolManager.settle{value: amountIn}();
            } else {
                IERC20Minimal(Currency.unwrap(currency)).transferFrom(owner, address(poolManager), amountIn);
                poolManager.settle();
            }
        }
    }

    function getBucket(bytes32 id, uint256 slot)
        public
        view
        returns (bool filled, uint256 amount0, uint256 amount1, uint128 liquidity)
    {
        Bucket storage bucket = buckets[id][slot];
        return (bucket.fulfilled, bucket.amount0, bucket.amount1, bucket.liquidity);
    }

    function getOrderSize(bytes32 id, uint256 slot, address user) public view returns (uint128) {
        return buckets[id][slot].sizes[user];
    }

    function getBucketId(PoolId poolId, int24 tick, bool zeroForOne) public pure returns (bytes32 bucketId) {
        return keccak256(abi.encode(PoolId.unwrap(poolId), tick, zeroForOne));
    }

    /// @notice IHooks
    function afterSwap(
        address sender,
        PoolKey calldata key,
        SwapParams calldata params,
        BalanceDelta delta,
        bytes calldata hookData
    ) external returns (bytes4, int128) {}

    function _getTick(PoolId poolId) private view returns (int24 tick) {
        (, tick,,) = StateLibrary.getSlot0(address(poolManager), poolId);
    }

    receive() external payable {}

    function getHookPermissions() public pure returns (Hooks.Permissions memory) {
        return Hooks.Permissions({
            beforeInitialize: false,
            afterInitialize: true,
            beforeAddLiquidity: false,
            afterAddLiquidity: false,
            beforeRemoveLiquidity: false,
            afterRemoveLiquidity: false,
            beforeSwap: false,
            afterSwap: true,
            beforeDonate: false,
            afterDonate: false,
            beforeSwapReturnDelta: false,
            afterSwapReturnDelta: false,
            afterAddLiquidityReturnDelta: false,
            afterRemoveLiquidityReturnDelta: false
        });
    }
}

