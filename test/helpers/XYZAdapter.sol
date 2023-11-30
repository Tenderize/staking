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

import { Adapter } from "core/adapters/Adapter.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";

import { StakingXYZ } from "./StakingXYZ.sol";

pragma solidity >=0.8.19;

contract XYZAdapter is Adapter {
    address immutable STAKINGXYZ;
    address immutable XYZ_TOKEN;

    constructor(address _stakingXYZ, address _xyz) {
        STAKINGXYZ = _stakingXYZ;
        XYZ_TOKEN = _xyz;
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) external view returns (uint256 amount) {
        (amount,) = StakingXYZ(STAKINGXYZ).unlocks(address(this), unlockID);
    }

    function unlockMaturity(uint256 unlockID) external view returns (uint256 maturity) {
        (, maturity) = StakingXYZ(STAKINGXYZ).unlocks(address(this), unlockID);
    }

    function unlockTime() external view returns (uint256) {
        return StakingXYZ(STAKINGXYZ).unlockTime();
    }

    function currentTime() external view returns (uint256) {
        return block.timestamp;
    }

    function stake(address, uint256 amount) external {
        ERC20(XYZ_TOKEN).approve(STAKINGXYZ, amount);
        StakingXYZ(STAKINGXYZ).stake(amount);
    }

    function unstake(address, uint256 amount) external returns (uint256 unlockID) {
        unlockID = StakingXYZ(STAKINGXYZ).unstake(amount);
    }

    function withdraw(address, uint256 unlockID) external returns (uint256 amount) {
        amount = StakingXYZ(STAKINGXYZ).withdraw(unlockID);
    }

    function rebase(address, uint256 currentStake) external returns (uint256 newStake) {
        if (block.timestamp < StakingXYZ(STAKINGXYZ).nextRewardTimeStamp()) return currentStake;
        StakingXYZ(STAKINGXYZ).claimrewards();
        newStake = StakingXYZ(STAKINGXYZ).staked(address(this));
    }

    function isValidator(address) external pure returns (bool) {
        return true;
    }
}
