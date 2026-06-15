// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {IPoolManager} from "./../../src/interfaces/IPoolManager.sol";
import {SafeCallback} from "./SafeCallback.sol";
import {CalldataDecoder} from "../libraries/CalldataDecoder.sol";
import {ActionConstants} from "../libraries/ActionConstants.sol";
import {IMsgSender} from "../interfaces/IMsgSender.sol";

/// @notice Abstract contract for performing a combination of actions on Uniswap v4.
/// @dev Suggested uint256 action values are defined in Actions.sol, however any definition can be used
abstract contract BaseActionsRouter is IMsgSender, SafeCallback {
    using CalldataDecoder for bytes;

    /// @notice emitted when different numbers of parameters and actions are provided
    error InputLengthMismatch();

    /// @notice emitted when an inheriting contract does not support an action
    error UnsupportedAction(uint256 action);

    function _unlockCallback(bytes calldata data) internal override returns (bytes memory) {
        (bytes calldata actions, bytes[] calldata params) = data.decodeActionsRouterParams();
    }

    function _executeActionWithoutUnlockCallback(bytes calldata actions, bytes[] calldata params) internal {
        uint256 numActions= actions
    }
    
}


