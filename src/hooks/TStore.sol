// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract TStore {
    bytes32 constant ACTION_SLOT = 0;
    modifier setAction(uint256 action) {
        require(_getAction() == 0, "locked");
        require(action > 0, "invalid action");
        _setAction(action);
        _;
        _setAction(0);
    }

    function _setAction(uint256 action) internal {
        assembly {
            tstore(ACTION_SLOT, action)
        }
    }

    function _getAction() internal view returns (uint256 action) {
        assembly {
            action := tload(ACTION_SLOT)
        }
    }
}
