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
import {Slot0, Slot0Library} from "../types/Slot0.sol";
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
    using Slot0Library for Slot0 global;

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

    /// @notice Thrown when tickLower is not below tickUpper
    /// @param tickLower The invalid tickLower
    /// @param tickUpper The invalid tickUpper
    error TicksMisordered(int24 tickLower, int24 tickUpper);

    /// @notice Thrown when tickLower is less than min tick
    /// @param tickLower The invalid tickLower
    error TickLowerOutOfBounds(int24 tickLower);

    /// @notice Thrown when tickUpper exceeds max tick
    /// @param tickUpper The invalid tickUpper
    error TickUpperOutOfBounds(int24 tickUpper);

    /// @notice Thrown when trying to initialize an already initialized pool
    error PoolAlreadyInitialized();

    /// @notice Thrown when trying to interact with a non-initialized pool
    error PoolNotInitialized();

    /// @notice Thrown when sqrtPriceLimitX96 on a swap has already exceeded its limit
    /// @param sqrtPriceCurrentX96 The invalid, already surpassed sqrtPriceLimitX96
    /// @param sqrtPriceLimitX96 The surpassed price limit
    error PriceLimitAlreadyExceeded(uint160 sqrtPriceCurrentX96, uint160 sqrtPriceLimitX96);

    /// @notice Thrown when sqrtPriceLimitX96 lies outside of valid tick/price range
    /// @param sqrtPriceLimitX96 The invalid, out-of-bounds sqrtPriceLimitX96
    error PriceLimitOutOfBounds(uint160 sqrtPriceLimitX96);

    /// @notice Thrown by donate if there is currently 0 liquidity, since the fees will not go to any liquidity providers
    error NoLiquidityToReceiveFees();

    /// @notice Thrown when trying to swap with max lp fee and specifying an output amount
    error InvalidFeeForExactOut();

    /// @dev Common checks for valid tick inputs.
    function checkTicks(int24 tickLower, int24 tickUpper) private pure {
        if (tickLower >= tickUpper) TicksMisordered.selector.revertWith(tickLower, tickUpper);
        if (tickLower < TickMath.MIN_TICK) TickLowerOutOfBounds.selector.revertWith(tickLower);
        if (tickUpper > TickMath.MAX_TICK) TickUpperOutOfBounds.selector.revertWith(tickUpper);
    }

    function initialize(State storage self, uint160 sqrtPriceX96, uint24 lpFee) internal returns (int24 tick) {
        if (self.slot0.sqrtPriceX96() != 0) PoolAlreadyInitialized.selector.revertWith();

        tick = TickMath.getTickAtSqrtPrice(sqrtPriceX96);

        // the initial protocolFee is 0 so doesn't need to be set
        self.slot0 = Slot0.wrap(bytes32(0)).setSqrtPriceX96(sqrtPriceX96).setTick(tick).setLpFee(lpFee);
    }

    function setProtocolFee(State storage self, uint24 protocolFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setProtocolFee(protocolFee);
    }

    /// @notice Only dynamic fee pools may update the lp fee.
    function setLPFee(State storage self, uint24 lpFee) internal {
        self.checkPoolInitialized();
        self.slot0 = self.slot0.setLpFee(lpFee);
    }

    struct ModifyLiquidityParams {
        // the address that owns the position
        address owner;
        // the lower and upper tick of the position
        int24 tickLower;
        int24 tickUpper;
        // any change in liquidity
        int128 liquidityDelta;
        // the spacing between ticks
        int24 tickSpacing;
        // used to distinguish positions of the same owner, at the same tick range
        bytes32 salt;
    }

    struct ModifyLiquidityState {
        bool flippedLower;
        uint128 liquidityGrossAfterLower;
        bool flippedUpper;
        uint128 liquidityGrossAfterUpper;
    }

    function modifyLiquidiry(State storage self, ModifyLiquidityParams memory param)
        internal
        returns (BalanceDelta delta, BalanceDelta feeDelta)
    {
        int128 liquidityDelta = params.liquidityDelta;
        int24 tickLower = params.tickLower;
        int24 tickUpper = params.tickUpper;

        checkTicks(tickLower, tickUpper);

        {
            ModifyLiquidityState memory state;
            if (liquidityDelta != 0) {
                (state.flippedLower, state.liquidityGrossAfterLower) =
                    udpateTick(self, tickLower, liquidityDelta, false);
                (state.flippedUpper, state.liquidityGrossAfterUpper) = udpateTick(self, tickUpper, liquidityDelta, true);

                if (liquidityDelta >= 0) {
                    uint128 maxLiquidityPerTick = tickSpacingToMaxLiquidityPerTick(params.tickSpacing);
                    if (state.liquidityGrossAfterLower > maxLiquidityPerTick) {
                        TickLiquidityOverflow.selector.revertWith(tickLower);
                    }
                    if (state.liquidityGrossAfterUpper > maxLiquidityPerTick) {
                        TickLiquidityOverflow.selector.revertWith(tickUpper);
                    }
                }

                if (state.flippedLower) self.tickBitmap.flip(tickLower, params.tickSpacing);
                if (state.flippedUpper) self.tickBitmap.flip(tickUpper, params.tickSpacing);
            }
            {
                (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128) =
                    getFeeGrowthInside(self, tickLower, tickUpper);

                Position.State storage position =
                    self.positions.get(params.owner, params.tickLower, params.tickUpper, params.salt);

                (uint256 feesOwed0, uint256 feesOwed1) =
                    position.update(liquidityDelta, feeGrowthInside0X128, feeGrowthInside1X128);

                feeDelta = toBalanceDelta(feesOwed0.toInt128(), feesOwed1.toInt128());
            }

            if (liquidityDelta < 0) {
                if (state.flippedLower) clearTick(self, tickLower);
                if (state.flippedUpper) clearTick(self, tickUpper);
            }
        }

        if (liquidityDelta != 0) {
            Slot0 _slot0 = self.slot0;
            (int24 tick, uint160 sqrtPriceX96) = (_slot0.tick(), _slot0.sqrtPriceX96());
            if (tick < tickLower) {
                // current tick is below the passed range; liquidity can only become in range by crossing from left to
                // right, when we'll need _more_ currency0 (it's becoming more valuable) so user must provide it
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(
                            TickMath.getSqrtPriceAtTick(tickLower),
                            TickMath.getSqrtPriceAtTick(tickUpper),
                            liquidityDelta
                        ).toInt128(),
                    0
                );
            } else if (tick < tickUpper) {
                delta = toBalanceDelta(
                    SqrtPriceMath.getAmount0Delta(sqrtPriceX96, TickMath.getSqrtPriceAtTick(tickUpper), liquidityDelta)
                        .toInt128(),
                    SqrtPriceMath.getAmount1Delta(TickMath.getSqrtPriceAtTick(tickLower), sqrtPriceX96, liquidityDelta)
                        .toInt128()
                );

                self.liquidity = LiquidityMath.addDelta(self.liquidity, liquidityDelta);
            } else {
                // current tick is above the passed range; liquidity can only become in range by crossing from right to
                // left, when we'll need _more_ currency1 (it's becoming more valuable) so user must provide it
                delta = toBalanceDelta(
                    0,
                    SqrtPriceMath.getAmount1Delta(
                            TickMath.getSqrtPriceAtTick(tickLower),
                            TickMath.getSqrtPriceAtTick(tickUpper),
                            liquidityDelta
                        ).toInt128()
                );
            }
        }
    }

    function udpateTick(State storage self, int24 tick, int128 liquidityDelta, bool upper)
        internal
        returns (bool flipped, uint128 liquidityGrossAfter)
    {
        TickInfo storage info = self.ticks[tick];

        uint128 liquidityGrossBefore = info.liquidityGross;
        int128 liquidityNetBefore = info.liquidityNet;

        liquidityGrossAfter = LiquidityMath.addDelta(liquidityGrossBefore, liquidityDelta);

        flipped = (liquidityGrossBefore == 0) != (liquidityGrossAfter == 0);

        if (liquidityGrossBefore == 0) {
            if (tick <= self.slot0.tick()) {
                info.feeGrowthOutside0X128 = self.feeGrowthGlobal0X128;
                info.feeGrowthOutside1X128 = self.feeGrowthGlobal1X128;
            }
        }

        int256 liquidityNet = upper ? liquidityNetBefore - liquidityDelta : liquidityGrossBefore + liquidityDelta;

        assembly ("memory-safe") {
            sstore(info.slot, or(and(liquidityGrossAfter, 0xffffffffffffffffffffffffffffffff), shl(128, liquidityNet)))
        }
    }

    /// @notice Derives max liquidity per tick from given tick spacing
    /// @dev Executed when adding liquidity
    /// @param tickSpacing The amount of required tick separation, realized in multiples of `tickSpacing`
    ///     e.g., a tickSpacing of 3 requires ticks to be initialized every 3rd tick i.e., ..., -6, -3, 0, 3, 6, ...
    /// @return result The max liquidity per tick
    function tickSpacingToMaxLiquidityPerTick(int24 tickSpacing) internal pure returns (uint128 result) {
        // Equivalent to:
        // int24 minTick = (TickMath.MIN_TICK / tickSpacing);
        // if (TickMath.MIN_TICK  % tickSpacing != 0) minTick--;
        // int24 maxTick = (TickMath.MAX_TICK / tickSpacing);
        // uint24 numTicks = maxTick - minTick + 1;
        // return type(uint128).max / numTicks;
        int24 MAX_TICK = TickMath.MAX_TICK;
        int24 MIN_TICK = TickMath.MIN_TICK;
        // tick spacing will never be 0 since TickMath.MIN_TICK_SPACING is 1
        assembly ("memory-safe") {
            tickSpacing := signextend(2, tickSpacing)
            let minTick := sub(sdiv(MIN_TICK, tickSpacing), slt(smod(MIN_TICK, tickSpacing), 0))
            let maxTick := sdiv(MAX_TICK, tickSpacing)
            let numTicks := add(sub(maxTick, minTick), 1)
            result := div(sub(shl(128, 1), 1), numTicks)
        }
    }

    /// @notice Retrieves fee growth data
    /// @param self The Pool state struct
    /// @param tickLower The lower tick boundary of the position
    /// @param tickUpper The upper tick boundary of the position
    /// @return feeGrowthInside0X128 The all-time fee growth in token0, per unit of liquidity, inside the position's tick boundaries
    /// @return feeGrowthInside1X128 The all-time fee growth in token1, per unit of liquidity, inside the position's tick boundaries
    function getFeeGrowthInside(State storage self, int24 tickLower, int24 tickUpper)
        internal
        view
        returns (uint256 feeGrowthInside0X128, uint256 feeGrowthInside1X128)
    {
        TickInfo storage lower = self.ticks[tickLower];
        TickInfo storage upper = self.ticks[tickUpper];
        int24 tickCurrent = self.slot0.tick();

        unchecked {
            if (tickCurrent < tickLower) {
                feeGrowthInside0X128 = lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 = lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            } else if (tickCurrent >= tickUpper) {
                feeGrowthInside0X128 = upper.feeGrowthOutside0X128 - lower.feeGrowthOutside0X128;
                feeGrowthInside1X128 = upper.feeGrowthOutside1X128 - lower.feeGrowthOutside1X128;
            } else {
                feeGrowthInside0X128 =
                    self.feeGrowthGlobal0X128 - lower.feeGrowthOutside0X128 - upper.feeGrowthOutside0X128;
                feeGrowthInside1X128 =
                    self.feeGrowthGlobal1X128 - lower.feeGrowthOutside1X128 - upper.feeGrowthOutside1X128;
            }
        }
    }

    /// @notice Clears tick data
    /// @param self The mapping containing all initialized tick information for initialized ticks
    /// @param tick The tick that will be cleared
    function clearTick(State storage self, int24 tick) internal {
        delete self.ticks[tick];
    }
}
