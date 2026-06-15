// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract TStore {
    bytes32 constant ACTION_SLOT = 0;

    // bytes32(uint256(keccak256("ReservesOf")) - 1)
    bytes32 constant MSG_SENDER_SLOT = 0x92d1ab7c2e926a8b0c0c873d3b809f7236b38c75135b8c33df2a722097f5486c;
    bytes32 constant MSG_VALUE_SLOT = 0x22b631f9536ce10e1c528e6fbfa1a31b8b90f6d7b15c83120655a1274d1c4141;

    modifier setAction(uint256 action) {
        require(_getAction() == 0, "locked");
        require(action > 0, "invalid action");
        _setAction(action);
        _;
        _setAction(0);
    }
    modifier msgStore(address sender, uint256 value) {
        _msgStore(sender, value);
        _;
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

    function _msgStore(address msgSender, uint256 msgValue) internal {
        require(_msgSender() == address(0));

        assembly {
            tstore(MSG_SENDER_SLOT, msgSender)
            tstore(MSG_VALUE_SLOT, msgValue)
        }
    }

    function _msgSender() internal view returns (address msgSender) {
        assembly {
            msgSender := tload(MSG_SENDER_SLOT)
        }
    }

    function _msgValue() internal view returns (uint256 msgValue) {
        assembly {
            msgValue := tload(MSG_VALUE_SLOT)
        }
    }
    // function setValue
}
