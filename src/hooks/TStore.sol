// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

contract TStore {
    bytes32 constant ACTION_SLOT = 0;

    // bytes32(uint256(keccak256("ReservesOf")) - 1)
    bytes32 constant MSG_SENDER_SLOT = bytes32(uint256(keccak256("msgSender")) - 1);
    bytes32 constant MSG_VALUE_SLOT = bytes32(uint256(keccak256("msgSender")) - 1);
    modifier setAction(uint256 action) {
        require(_getAction() == 0, "locked");
        require(action > 0, "invalid action");
        _setAction(action);
        _;
        _setAction(0);
    }
    modifier msgStore(uint256 action) {
        _msgStore(msg.sender, msg.value);
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
        require(getSender() == address(0));

        assembly {
            tstore(MSG_SENDER_SLOT, msgSender)
            tstore(MSG_VALUE_SLOT, msgSender)
        }
    }

    function _msgSender() internal returns (address msgSender) {
        assembly {
            msgSender := tload(MSG_SENDER_SLOT, msgSender)
        }
    }

    function _msgValue() internal returns (address msgValue) {
        assembly {
            msgValue := tload(MSG_SENDER_SLOT, msgValue)
        }
    }
    // function setValue
}
