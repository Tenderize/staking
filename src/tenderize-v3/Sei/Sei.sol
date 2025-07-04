// SPDX-License-Identifier: MIT
//
//  _____              _           _
// |_   _|            | |         (_)
//   | | ___ _ __   __| | ___ _ __ _ _______
//   | |/ _ \ '_ \ / _` |/ _ \ '__| |_  / _ \
//   | |  __/ | | | (_| |  __/ |  | |/ /  __/
//   \_/\___|_| |_|\__,_|\___|_|  |_/___\___|
//
// Copyright (c) Tenderize Labs Ltd

pragma solidity ^0.8.25;

address payable constant SEI_STAKING_PRECOMPILE_ADDRESS = payable(0x0000000000000000000000000000000000001005);

struct Balance {
    uint256 amount;
    string denom;
}

struct DelegationDetails {
    string delegator_address;
    uint256 shares;
    uint256 decimals;
    string validator_address;
}

struct Delegation {
    Balance balance;
    DelegationDetails delegation;
}

interface ISeiStaking {
    /// @notice Delegates Sei to the specified validator.
    /// @dev This function truncates msg.value to 6 decimal places for interaction with the staking module
    /// @param valAddress The Sei address of the validator.
    /// @return success Whether the delegation was successful.
    function delegate(string memory valAddress) external payable returns (bool success);

    /// @notice Redelegates Sei from one validator to another.
    /// @dev The amount should be in 6 decimal precision, not 18. 1 SEI = 1_000_000 uSEI
    /// @param srcAddress The Sei address of the validator to move delegations from.
    /// @param dstAddress The Sei address of the validator to move delegations to.
    /// @param amount The amount of Sei to move from srcAddress to dstAddress.
    /// @return success Whether the redelegation was successful.
    function redelegate(string memory srcAddress, string memory dstAddress, uint256 amount) external returns (bool success);

    /// @notice Undelegates Sei from the specified validator.
    /// @dev The amount should be in 6 decimal precision, not 18. 1 SEI = 1_000_000 uSEI
    /// @param valAddress The Sei address of the validator to undelegate from.
    /// @param amount The amount of Sei to undelegate.
    /// @return success Whether the undelegation was successful.
    function undelegate(string memory valAddress, uint256 amount) external returns (bool success);

    /// @notice Queries delegation for a given delegator and validator address.
    /// @param delegator The x0 or Sei address of the delegator.
    /// @param valAddress The Sei address of the validator.
    /// @return delegation The delegation information. Shares in DelegationDetails are usually returned as decimals.
    /// To calculate the actual amount, divide the shares by decimals.
    function delegation(address delegator, string memory valAddress) external view returns (Delegation memory delegation);
}
