// SPDX-License-Identifier: MIT

import {PoolKey} from "./../../types/PoolKey.sol";
import {SafeCallback} from "./SafeCallback.sol";
import {SwapParams} from "./../../types/PoolOperation.sol";
import {TickMath} from "./../../libraries/TickMath.sol";
import {BalanceDelta} from "./../../types/BalanceDelta.sol";
import {QuoterRevert} from "./../libraries/QuoterRevert.sol";
import {PoolId} from "./../../types/PoolId.sol";
import {IPoolManager} from "./../../interfaces/IPoolManager.sol";

abstract contract BaseV4Quoter is SafeCallback {
    using QuoterRevert for *;

    error NotEnoughLiquidity(PoolId poolId);
    error NotSelf();
    error UnexpectedCallSuccess();

    modifier selfOnly() {
        if (msg.sender != address(this)) revert NotSelf();
        _;
    }

    constructor(IPoolManager _poolManager) SafeCallback(_poolManager) {}

    function _swap(PoolKey memory key, bool zeroForOne, int256 amountSpecified, bytes memory hookData)
        internal
        returns (BalanceDelta swapDelta)
    {
        swapDelta = poolManager.swap(
            key,
            SwapParams({
                zeroForOne: zeroForOne,
                amountSpecified: amountSpecified,
                sqrtPriceLimitX96: zeroForOne ? TickMath.MIN_SQRT_PRICE + 1 : TickMath.MAX_SQRT_PRICE - 1
            }),
            hookData
        );

        int128 swapAmount = (zeroForOne == (amountSpecified < 0)) ? swapDelta.amount0() : swapDelta.amount1();
        if (swapAmount != amountSpecified) revert NotEnoughLiquidity(key.toId());
    }

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (bool success, bytes memory returnData) = address(this).call(data);
        // Every quote path gathers a quote, and then reverts either with QuoteSwap(quoteAmount) or alternative error
        if (success) revert UnexpectedCallSuccess();
        // Bubble the revert string, whether a valid quote or an alternative error
        returnData.bubbleReason();
    }
}
