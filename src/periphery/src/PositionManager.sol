// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "./../../interfaces/IPoolManager.sol";
import {PoolKey} from "./../../types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "./../../types/Currency.sol";
import {BalanceDelta} from "./../../types/BalanceDelta.sol";
import {SafeCallback} from "./../base/SafeCallback.sol";
import {SafeCast} from "./../../libraries/SafeCast.sol";
import {Position} from "./../../libraries/Position.sol";
import {StateLibrary} from "./../../libraries/StateLibrary.sol";
import {TransientStateLibrary} from "./../../libraries/TransientStateLibrary.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";
import {TickMath} from "./../../libraries/TickMath.sol";
import {ModifyLiquidityParams, SwapParams} from "./../../types/PoolOperation.sol";

import {IPositionDescriptor} from "./../interfaces/IPositionDescriptor.sol";
import {ERC721Permit_v4} from "./../base/ERC721Permit_v4.sol";
import {ReentrancyLock} from "./../base/ReentrancyLock.sol";
import {IPositionManager} from "./../interfaces/IPositionManager.sol";
import {Multicall_v4} from "./../base/Multicall_v4.sol";
import {PoolInitializer_v4} from "./../base/PoolInitializer_v4.sol";
import {DeltaResolver} from "./../base/DeltaResolver.sol";
import {BaseActionsRouter} from "./../base/BaseActionsRouter.sol";
import {Actions} from "./../libraries/Actions.sol";
import {Notifier} from "./../base/Notifier.sol";
import {CalldataDecoder} from "./../libraries/CalldataDecoder.sol";
import {Permit2Forwarder} from "./../base/Permit2Forwarder.sol";
import {SlippageCheck} from "./../libraries/SlippageCheck.sol";
import {PositionInfo, PositionInfoLibrary} from "./../libraries/PositionInfoLibrary.sol";
import {LiquidityAmounts} from "./../libraries/LiquidityAmounts.sol";
import {NativeWrapper} from "./../base/NativeWrapper.sol";
import {IWETH9} from "./../interfaces/external/IWETH9.sol";

contract PositionManager is
    IPositionManager,
    ERC721Permit_v4,
    PoolInitializer_v4,
    Multicall_v4,
    DeltaResolver,
    ReentrancyLock,
    BaseActionsRouter,
    Notifier,
    Permit2Forwarder,
    NativeWrapper
{
    using StateLibrary for IPoolManager;
    using TransientStateLibrary for IPoolManager;
    using SafeCast for uint256;
    using SafeCast for int256;
    using CalldataDecoder for bytes;
    using SlippageCheck for BalanceDelta;

    uint256 public nextTokenId = 1;

    mapping(uint256 tokenId => PositionInfo info) public positionInfo;
    mapping(bytes25 poolId => PoolKey poolKey) public poolKeys;

    IPositionDescriptor public immutable tokenDescriptor;

    modifier checkDeadline(uint256 deadline) {
        if (block.timestamp > deadline) revert DeadlinePassed(deadline);

        _;
    }

    modifier onlyIfApproved(address caller, uint256 tokenId) override {
        if (!_isApprovedOrOwner(caller, tokenId)) revert NotApproved(caller);

        _;
    }

    modifier onlyIfPoolManagerLocked() override {
        if (poolManager.isUnlocked()) revert PoolManagerMustBeLocked();

        _;
    }

    constructor(
        IPoolManager _poolManager,
        IAllowanceTransfer _permit2,
        uint256 _unsubscribeGasLimit,
        IPositionDescriptor _tokenDescriptor,
        IWETH9 _weth9
    )
        BaseActionsRouter(_poolManager)
        Permit2Forwarder(_permit2)
        ERC721Permit_v4("Uniswap v4 Positions NFT", "UNI-V4-POSM")
        Notifier(_unsubscribeGasLimit)
        NativeWrapper(_weth9)
    {
        tokenDescriptor = _tokenDescriptor;
    }

    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        return IPositionDescriptor(tokenDescriptor).tokenURI(this, tokenId);
    }

    function _handleAction(uint256 action, bytes calldata params) internal virtual override {
        if (action < Actions.SETTLE) {
            if (action == Actions.INCREASE_LIQUIDITY) {
                (uint256 tokenId, uint256 liquidity, uint128 amount0Max, uint128 amount1Max, bytes calldata hookData) =
                    params.decodeModifyLiquidityParams();
                _increase(tokenId, liquidity, amount0Max, amount1Max, hookData);

                return;
            } else if (action == Actions.INCREASE_LIQUIDITY_FROM_DELTAS) {
                //_increaseFromDeltas
            } else if (action == Actions.DECREASE_LIQUIDITY) {
                // _decrease
            } else if (action == Actions.MINT_POSITION) {
                // _mint
            } else if (action == Actions.MINT_POSITION_FROM_DELTAS) {
                // _mintFromDeltas
            } else if (action == Actions.BURN_POSITION) {}
        } else {
            if (action == Actions.SETTLE_PAIR) {
                (Currency c0, Currency c1) = params.decodeCurrencyPair();
                _settlePair(c0, c1);

                return;
            } else if (action == Actions.TAKE_PAIR) {
                (Currency c0, Currency c1, address recipient) = params.decodeCurrencyPairAndAddress();
                _takePair(c0, c1, _mapRecipient(recipient));

                return;
            } else if (action == Actions.SETTLE) {
                (Currency currency, uint256 amount, bool payerIsUser) = params.decodeCurrencyUint256AndBool();
                _settle(currency, _mapPayer(payerIsUser), _mapSettleAmount(amount, currency));

                return;
            } else if (action == Actions.TAKE) {
                (Currency currency, address recipient, uint256 amount) = params.decodeCurrencyAddressAndUint256();
                _take(currency, recipient, amount);

                return;
            } else if (action == Actions.CLOSE_CURRENCY) {
                Currency currency = params.decodeCurrency();
                _close(currency);

                return;
            } else if (action == Actions.CLEAR_OR_TAKE) {
                (Currency currency, uint256 amountMax) = params.decodeCurrencyAndUint256();
                _clearOrTake(currency, amountMax);

                return;
            } else if (action == Actions.SWEEP) {
                (Currency currency, address to) = params.decodeCurrencyAndAddress();
                _sweep(currency, _mapRecipient(to));

                return;
            } else if (action == Actions.WRAP) {
                uint256 amount = params.decodeUint256();
                _wrap(_mapWrapUnwrapAmount(CurrencyLibrary.ADDRESS_ZERO, amount, Currency.wrap(address(WETH9))));

                return;
            } else if (action == Actions.UNWRAP) {
                uint256 amount = params.decodeUint256();
                _unwrap(_mapWrapUnwrapAmount(Currency.wrap(address(WETH9)), amount, CurrencyLibrary.ADDRESS_ZERO));
            }
        }

        revert UnsupportedAction(action);
    }

    function _increase(
        uint256 tokenId,
        uint256 liquidity,
        uint128 amount0Max,
        uint128 amount1Max,
        bytes memory hookData
    ) internal onlyIfApproved(msgSender(), tokenId) {
        (PoolKey memory key, PositionInfo info) = getPoolAndPositionInfo(tokenId);
        (BalanceDelta delta, BalanceDelta feeDelta) =
            _modifyLiquidity(key, info, liquidity.toInt256(), bytes32(tokenId), hookData);

        (delta - feeDelta).validateMaxIn(amount0Max, amount1Max);
    }

    function _modifyLiquidity(
        PoolKey memory key,
        PositionInfo info,
        int256 liquidityChange,
        bytes32 salt,
        bytes memory hookData
    ) internal returns (BalanceDelta delta, BalanceDelta fees) {
        (delta, fees) = poolManager.modifyLiquidity(
            key,
            ModifyLiquidityParams({
                tickLower: info.tickLower(), tickUpper: info.tickUpper(), liquidityDelta: liquidityChange, salt: salt
            }),
            hookData
        );

        emit ModifyPosition(key.toId(), msgSender(), info.tickLower(), info.tickUpper(), liquidityChange, salt);

        if (info.hasSubscriber()) {
            _notifyModifyLiquidity(uint256(salt), liquidityChange, fees);
        }
    }

    function _takePair(Currency currency0, Currency currency1, address recipient) internal {
        _take(currency0, recipient, _getFullCredit(currency0));
        _take(currency1, recipient, _getFullCredit(currency1));
    }

    function _settlePair(Currency currency0, Currency currency1) internal {
        address payer = msgSender();
        _settle(currency0, payer, _getFullDebt(currency0));
        _settle(currency1, payer, _getFullDebt(currency1));
    }

    function _close(Currency currency) internal {
        int256 delta = poolManager.currencyDelta(address(this), currency);

        address caller = msgSender();

        if (delta < 0) {
            _settle(currency, caller, uint256(-delta));
        } else {
            _take(currency, caller, uint256(delta));
        }
    }

    function _clearOrTake(Currency currency, uint256 amountMax) internal {
        uint256 credit = _getFullCredit(currency);
        if (credit == 0) return;

        if (credit <= amountMax) {
            poolManager.clear(currency, credit);
        } else {
            _take(currency, msgSender(), credit);
        }
    }

    function _sweep(Currency currency, address recipient) internal virtual {
        uint256 balance = currency.balanceOfSelf();
        if (balance > 0) currency.transfer(recipient, balance);
    }

    function _pay(Currency currency, address payer, uint256 amount) internal virtual override {
        if (payer == address(this)) {
            currency.transfer(address(poolManager), amount);
        } else {
            permit2.transferFrom(payer, address(poolManager), uint160(amount), Currency.unwrap(currency));
        }
    }

    function getPoolAndPositionInfo(uint256 tokenId) public view returns (PoolKey memory key, PositionInfo info) {
        info = positionInfo[tokenId];
        key = poolKeys[info.poolId()];
    }

    function msgSender() public view override returns (address) {
        return _getLocker();
    }
}
