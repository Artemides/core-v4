// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IPoolManager} from "./../../interfaces/IPoolManager.sol";
import {PoolKey} from "./../../types/PoolKey.sol";
import {Currency, CurrencyLibrary} from "./../../types/Currency.sol";
import {BalanceDelta} from "./../../types/BalanceDelta.sol";
import {SafeCallback} from "./../base/SafeCallback.sol";

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
{}
