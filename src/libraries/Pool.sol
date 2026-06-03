// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import {SafeCast} from "./SafeCast.sol";
import {TickBitmap} from "./TickBitmap.sol";
import {Position} from "./Position.sol";
import {UnsafeMath} from "./UnsafeMath.sol";
import {FixedPoint128} from "./FixedPoint128.sol";
import {TickMath} from "./TickMath.sol";
import {SqrtPriceMath} from "./SqrtPriceMath.sol";
import {SwapMath} from "./SwapMath.sol";
import {BalanceDelta, toBalanceDelta, BalanceDeltaLibrary} from "../types/BalanceDelta.sol";
import {Slot0} from "../types/Slot0.sol";
import {ProtocolFeeLibrary} from "./ProtocolFeeLibrary.sol";
import {LiquidityMath} from "./LiquidityMath.sol";
import {LPFeeLibrary} from "./LPFeeLibrary.sol";
import {CustomRevert} from "./CustomRevert.sol";

library Pool {
    using SafeCast for *;
    using TickBitmap for mapping(int16 => uint256);
    using Position for mapping(bytes32 => Position.State);
    using Position for Position.State;
    using Pool for State;
    using ProtocolFeeLibrary for *;
    using LPFeeLibrary for uint24;
    using CustomRevert for bytes4;

    struct TickInfo {
        uint128 liquidityGross;
        int128 liquidityNet;
        uint256 feeGrowthOutside0X128;
        uint256 feeGrowthOutside1X128;
    }

    struct State {
        Slot0 slot0;
        uint256 feeGrowthGlobal0X128;
        uint256 feeGrowthGlobal1X128;
        uint128 liquidity;
        mapping(int24 tick => TickInfo) ticks;
        mapping(int16 wordPos => uint256 bitPos) tickBitmap;
        mapping(bytes32 key => Position.State) positions;
    }
}
