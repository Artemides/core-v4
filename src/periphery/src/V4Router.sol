// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IPoolManager} from "./../../interfaces/IPoolManager.sol";
import {ImmutableState} from "./../base/ImmutableState.sol";
import {SwapParams} from "./../../types/PoolOperation.sol";
import {PoolKey} from "./../../types/PoolKey.sol";
import {TickMath} from "./../../libraries/TickMath.sol";
import {BalanceDelta} from "./../../types/BalanceDelta.sol";
import {SafeCast} from "./../../libraries/SafeCast.sol";

import {IV4Router} from "./../interfaces/IV4Router.sol";
import {DeltaResolver} from "./../base/DeltaResolver.sol";
import {ActionConstants} from "./../libraries/ActionConstants.sol";
import {PathKey} from "./../libraries/PathKey.sol";
import {Currency} from "./../../types/Currency.sol";

contract V4Router is IV4Router, ImmutableState, DeltaResolver {
    using SafeCast for *;

    uint256 private constant PRECISION = 1e36;

    constructor(IPoolManager _pm) ImmutableState(_pm) {}

    function _swapExactInputSingle(IV4Router.ExactInputSingleParams memory params) private {
        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) {
            amountIn =
                _getFullCredit(params.zeroForOne ? params.poolKey.currency0 : params.poolKey.currency1).toUint128();
        }
        uint128 amountOut =
            _swap(params.poolKey, params.zeroForOne, -int256(uint256(amountIn)), params.hookData).toUint128();

        if (amountOut < params.amountOutMinimum) revert V4TooLittleReceived(params.amountOutMinimum, amountOut);

        if (params.minHopPriceX36 != 0) {
            uint256 priceX36 = uint256(amountOut) * PRECISION / amountIn;
            if (priceX36 < params.minHopPriceX36) {
                revert V4TooLittleReceivedPerHopSingle(params.minHopPriceX36, priceX36);
            }
        }
    }

    function _swapExactInput(IV4Router.ExactInputParams calldata params) private {
        uint256 swaps = params.path.length;
        Currency currencyIn = params.currencyIn;

        uint128 amountIn = params.amountIn;
        if (amountIn == ActionConstants.OPEN_DELTA) amountIn = _getFullCredit(currencyIn).toUint128();

        uint256 perHopPriceLength = params.minHopPriceX36.length;
        if (perHopPriceLength != 0 && perHopPriceLength != swaps) revert InvalidHopPriceLength();

        PathKey calldata pathKey;
        uint128 amountOut;

        for (uint256 i = 0; i < swaps; i++) {
            pathKey = params.path[i];
            (PoolKey memory poolKey, bool zeroForOne) = pathKey.getPoolAndSwapDirection(currencyIn);

            amountOut = _swap(poolKey, zeroForOne, -int256(uint256(amountIn)), pathKey.hookData).toUint128();

            if (perHopPriceLength != 0) {
                uint256 priceX36 = amountOut * PRECISION / amountIn;
                uint256 minPrice = params.minHopPriceX36[i];
                if (priceX36 < minPrice) revert V4TooLittleReceivedPerHop(i, minPrice, priceX36);
            }

            amountIn = amountOut;
            currencyIn = pathKey.intermediateCurrency;
        }

        if (amountOut < params.amountOutMinimum) revert V4TooLittleReceived(params.amountOutMinimum, amountOut);
    }

    function _swapExactOutputSingle(IV4Router.ExactOutputSingleParams calldata params) private {
        uint128 amountOut = params.amountOut;

        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut =
                _getFullDebt(params.zeroForOne ? params.poolKey.currency1 : params.poolKey.currency0).toUint128();
        }

        int128 rawAmountIn = _swap(params.poolKey, params.zeroForOne, amountOut.toInt256(), params.hookData);

        uint128 amountIn = uint256(-int256(rawAmountIn)).toUint128();

        if (amountIn > params.amountInMaximum) revert V4TooMuchRequested(params.amountInMaximum, amountIn);

        if (params.minHopPriceX36 != 0) {
            uint256 priceX36 = uint256(amountOut) * PRECISION / amountIn;
            if (priceX36 < params.minHopPriceX36) {
                revert V4TooMuchRequestedPerHopSingle(params.minHopPriceX36, priceX36);
            }
        }
    }

    function _swapExactOutput(IV4Router.ExactOutputParams calldata params) private {
        uint256 pathLength = params.path.length;

        Currency currencyOut = params.currencyOut;

        uint128 amountOut = params.amountOut;
        if (amountOut == ActionConstants.OPEN_DELTA) {
            amountOut = _getFullDebt(currencyOut).toUint128();
        }

        uint256 hopsLength = params.minHopPriceX36.length;
        if (hopsLength != 0 && hopsLength != pathLength) revert InvalidHopPriceLength();

        PathKey calldata pathKey;
        uint128 amountIn;
        for (uint256 i = pathLength; i > 0; i--) {
            pathKey = params.path[i - 1];
            (PoolKey memory poolKey, bool zeroForOne) = pathKey.getPoolAndSwapDirection(currencyOut);

            int128 rawAmountIn = _swap(poolKey, zeroForOne, amountOut.toInt256(), pathKey.hookData);
            amountIn = uint128(-rawAmountIn);

            if (hopsLength != 0) {
                uint256 price = amountOut * PRECISION / amountIn;
                uint256 minPrice = params.minHopPriceX36[i - 1];
                if (minPrice < price) V4TooMuchRequestedPerHop(i - 1, minPrice, price);
            }

            amountOut = amountIn;
            currencyOut = pathKey.intermediateCurrency;
        }
        if (amountIn > params.amountInMaximum) revert V4TooMuchRequested(params.amountInMaximum, amountIn);
    }

    function _swap(PoolKey memory poolKey, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (int128 amountOut)
    {
        unchecked {

            BalanceDelta swapDelta = poolManager.swap(
                poolKey,
                SwapParams({
                    zeroForOne: zeroForOne,
                    amountSpecified: amountSpecified,
                    sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
                }),
                hookData
            );

            amountOut = zeroForOne == amountSpecified < 0 ? swapDelta.amount1() : swapDelta.amount1();
        }
    }
}
