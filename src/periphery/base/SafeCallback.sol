// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IPoolManager} from "./../../interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./../../interfaces/callback/IUnlockCallback.sol";
import {ImmutableState} from "./ImmutableState.sol";

abstract contract SafeCallback is ImmutableState, IUnlockCallback {
    constructor(IPoolManager _poolManager) ImmutableState(_poolManager) {}

    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        return _unlockCallback(data);
    }

    function _unlockCallback(bytes calldata data) internal virtual returns (bytes memory);
}
