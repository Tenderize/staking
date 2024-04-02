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

pragma solidity >=0.8.19;

uint256 constant UNSTAKE_TIME = 21 days;

enum BondStatus {
    Unbonded,
    Unbonding,
    Bonded
}

struct UnbondingDelegation {
    uint256 initialAmount;
    uint256 amount;
    uint256 creationHeight;
    uint256 completionTime;
}

struct StakingPool {
    uint256 totalShares;
    uint256 totalTokens;
    BondStatus status;
    bool jailed;
}

interface ISei {
    // Transactions
    function delegate(address validator, uint256 amount) external returns (bool success);

    function redelegate(address src, address dst, uint256 amount) external returns (bool success);

    function undelegate(address validator, uint256 amount) external returns (uint256 unbondingID);

    function getDelegation(address delegator, address validator) external view returns (uint256 shares);

    function getStakingPool(address validator) external view returns (StakingPool memory);

    function getUnbondingDelegation(address validator, uint256 unbondingID) external view returns (UnbondingDelegation memory);
}
