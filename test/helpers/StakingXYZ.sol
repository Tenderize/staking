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

import { ERC20 } from "solmate/tokens/ERC20.sol";

pragma solidity >=0.8.19;

contract StakingXYZ {
    mapping(address => uint256) public staked;

    address immutable token;
    uint256 public nextRewardTimeStamp;

    uint256 constant rewardTime = 1 days;
    uint256 constant unlockTime = 1 minutes;

    struct Unlock {
        uint256 amount;
        uint256 maturity;
    }

    mapping(address => mapping(uint256 => Unlock)) public unlocks;
    mapping(address => uint256) public unlockCount;

    constructor(address _token) {
        token = _token;
    }

    function stake(uint256 amount) external {
        require(amount > 0, "amount must be greater than 0");
        ERC20(token).transferFrom(msg.sender, address(this), amount);
        staked[msg.sender] = staked[msg.sender] + amount;
    }

    function unstake(uint256 amount) external returns (uint256 unlockID) {
        staked[msg.sender] -= amount;
        unlockID = unlockCount[msg.sender]++;
        unlocks[msg.sender][unlockID] = Unlock(amount, block.timestamp + unlockTime);
    }

    function withdraw(uint256 id) external returns (uint256) {
        Unlock memory unlock = unlocks[msg.sender][id];
        require(unlock.maturity <= block.timestamp, "unlock time not reached");
        delete unlocks[msg.sender][id];
        ERC20(token).transfer(msg.sender, unlock.amount);
        return unlock.amount;
    }

    function claimrewards() external {
        if (block.timestamp < nextRewardTimeStamp) return;
        staked[msg.sender] = staked[msg.sender] * 1.007e6 / 1e6;
        nextRewardTimeStamp = block.timestamp;
    }
}
