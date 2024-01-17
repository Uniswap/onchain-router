// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

/// @notice Detects the buy and sell fee for a fee-on-transfer token
interface IFeeOnTransferDetector {
    struct TokenFees {
        uint256 buyFeeBps;
        uint256 sellFeeBps;
    }

    /// @notice detects FoT fees for a single token
    function validate(address token, address baseToken, uint256 amountToBorrow)
        external
        returns (TokenFees memory fotResult);
}
