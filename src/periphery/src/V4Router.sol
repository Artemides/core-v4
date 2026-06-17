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
