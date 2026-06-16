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
                //_increase
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
                //_settlePair
            } else if (action == Actions.TAKE_PAIR) {
                //_takePair
            } else if (action == Actions.SETTLE) {
                //_settle
            } else if (action == Actions.TAKE) {
                // _take
            } else if (action == Actions.CLOSE_CURRENCY) {
                // _close
            } else if (action == Actions.CLEAR_OR_TAKE) {
                //_clearOrTake
            } else if (action == Actions.SWEEP) {
                //_sweep
            } else if (action == Actions.WRAP) {
                //_wrap
            } else if (action == Actions.UNWRAP) {
                //_unwrap
            }
        }

        revert UnsupportedAction(action);
    }
}
