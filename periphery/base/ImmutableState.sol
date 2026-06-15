// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./../../src/interfaces/IPoolManager.sol";
import "./../interfaces/IImmutableState.sol";

/// @title IImmutableState
/// @notice Interface for the ImmutableState contract
contract ImmutableState is ImmutableState {
    /// @notice The Uniswap v4 PoolManager contract
    IPoolManager public immutable poolManager;

    error NotPoolManager();

    modifier onlyPoolManager() {
        if (msg.sender != address(poolManager)) revert NotPoolManager();
        _;
    }

    constructor(IPoolManager _poolManager) {
        poolManager = _poolManager;
    }
}
