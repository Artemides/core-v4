// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IPoolManager} from "./../../src/interfaces/IPoolManager.sol";
import {IUnlockCallback} from "./../../src/interfaces/callback/IUnlockCallback.sol";
import {ImmutableState} from "./ImmutableState.sol";

contract SafeCallback is IUnlockCallback, ImmutableState {
    constructor(IPoolManager _poolManager) ImmutableState(_poolManager) {}

    function unlockCallback(bytes calldata data) external onlyPoolManager returns (bytes memory) {
        return _unlockCallback(data);
    }

    function _unlockCallback(bytes calldata data) internal virtual returns (bytes memory);
}
