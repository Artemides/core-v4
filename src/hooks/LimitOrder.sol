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

abstract contract LimitOrderHook is TStore, IUnlockCallback {
    using SafeCast for int128;

    uint256 constant ADD_LIQUIDITY = 1;
    uint256 constant REMOVE_LIQUIDITY = 2;

    struct Bucket {
        bool fulfilled;
        uint256 amount0;
        uint256 amount1;
        mapping(address user => uint256 amount) sizes;
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

    error NotPoolManager();
    error InvalidTick();

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
        bytes memory amountInBytes = poolManager.unlock(data);

        uint256 amountIn = abi.decode(amountInBytes, (uint256));

        bytes32 bucketId = getBucketId(id, tickLower, zeroForOne);
        uint256 currentSlot = slots[bucketId];

        Bucket storage bucket = buckets[bucketId][currentSlot];
        bucket.sizes[msg.sender] = liquidity;

        bucket.amount0 += zeroForOne ? amountIn : 0;
        bucket.amount1 += zeroForOne ? 0 : amountIn;

        int24 initialized = ticks[id];
        if (initialized == 0) {
            ticks[id] = tickLower;
        }

        emit Place(PoolId.unwrap(id), currentSlot, msg.sender, tickLower, zeroForOne, liquidity);
    }

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        (address owner, PoolKey memory poolKey, ModifyLiquidityParams memory params) =
            abi.decode(data, (address, PoolKey, ModifyLiquidityParams));

        (BalanceDelta delta,) = poolManager.modifyLiquidity(poolKey, params, "");

        (int128 amount0, int128 amount1) = (delta.amount0(), delta.amount1());
        bool zeroForOne = amount0 < 0;

        uint256 amountIn = (-(zeroForOne ? amount0 : amount1)).toUint256();
        Currency currencyIn = zeroForOne ? poolKey.currency0 : poolKey.currency1;

        poolManager.sync(currencyIn);
        if (currencyIn.isAddressZero()) {
            poolManager.settle{value: amountIn}();
        } else {
            IERC20Minimal(Currency.unwrap(currencyIn)).transferFrom(owner, address(poolManager), amountIn);
            poolManager.settle();
        }

        return abi.encode(amountIn);
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

