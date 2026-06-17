// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {ParseBytes} from "./../../libraries/ParseBytes.sol";

library QuoterRevert {
    using QuoterRevert for bytes;
    using ParseBytes for bytes;

    /// @notice error thrown when invalid revert bytes are thrown by the quote
    error UnexpectedRevertBytes(bytes revertData);

    /// @notice error thrown containing the quote as the data, to be caught and parsed later
    error QuoteSwap(uint256 amount);

    function revertQuote(uint256 quoteAmount) internal pure {
        revert QuoteSwap(quoteAmount);
    }

    function bubbleReason(bytes memory revertData) internal pure {
        assembly {
            revert(add(revertData, 0x20), mload(revertData))
        }
    }

    function parseQuoteAmount(bytes memory reason) internal pure returns (uint256 quoteAmount) {
        // If the error doesnt start with QuoteSwap, we know this isnt a valid quote to parse
        // Instead it is another revert that was triggered somewhere in the simulation
        if (reason.parseSelector() != QuoteSwap.selector) {
            revert UnexpectedRevertBytes(reason);
        }

        // reason -> reason+0x1f is the length of the reason string
        // reason+0x20 -> reason+0x23 is the selector of QuoteSwap
        // reason+0x24 -> reason+0x43 is the quoteAmount
        assembly ("memory-safe") {
            quoteAmount := mload(add(reason, 0x24))
        }
    }
}

