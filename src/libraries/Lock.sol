// SPDX-License-Identifier: MIT

pragma solidity 0.8.28;

library Lock {
    bytes32 internal constant IS_UNLOCKED_SLOT = 0xc090fc4683624cfc3884e9d8de5eca132f2d0ec062aff75d43c0465d5ceeab23;

    function lock() internal {
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }

    function unlock() internal {
        assembly ("memory-safe") {
            tstore(IS_UNLOCKED_SLOT, true)
        }
    }

    function isUnlocked() internal view returns (bool unlocked) {
        assembly {
            unlocked := tload(IS_UNLOCKED_SLOT)
        }
    }
}
