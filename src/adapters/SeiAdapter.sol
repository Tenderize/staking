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

uint256 constant VERSION = 1;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Adapter, WithdrawPending as WithdrawPendingError } from "core/adapters/Adapter.sol";
import { ISei, StakingPool, UnbondingDelegation, BondStatus, UNSTAKE_TIME } from "core/adapters/interfaces/ISei.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

address constant SEI_STAKING_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000001005;
ISei constant SEI_STAKING_CONTRACT = ISei(SEI_STAKING_PRECOMPILE_ADDRESS);

contract SeiAdapter is Adapter {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.sei.adapter.storage.location")) - 1;

    struct Storage {
        address validator;
    }

    function _loadStorage() internal pure returns (Storage storage $) {
        uint256 slot = STORAGE;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function previewDeposit(address validator, uint256 assets) external view override returns (uint256) {
        return _previewDeposit(validator, assets);
    }

    function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
        UnbondingDelegation memory unbond = SEI_STAKING_CONTRACT.getUnbondingDelegation(_loadStorage().validator, unlockID);
        return unbond.amount;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        UnbondingDelegation memory unbond = SEI_STAKING_CONTRACT.getUnbondingDelegation(_loadStorage().validator, unlockID);
        return unbond.completionTime;
    }

    function unlockTime() external view override returns (uint256) {
        return UNSTAKE_TIME;
    }

    function currentTime() external view override returns (uint256) {
        return block.timestamp;
    }

    function isValidator(address validator) public view override returns (bool) {
        return SEI_STAKING_CONTRACT.getStakingPool(validator).status == BondStatus.Bonded;
    }

    function stake(address validator, uint256 amount) external payable override returns (uint256 out) {
        out = _previewDeposit(validator, amount);
        SEI_STAKING_CONTRACT.delegate(validator, amount);
    }

    function unstake(address validator, uint256 amount) external override returns (uint256 unlockID) {
        unlockID = SEI_STAKING_CONTRACT.undelegate(validator, amount);
    }

    function withdraw(address validator, uint256 unlockID) external override returns (uint256 amount) {
        UnbondingDelegation memory unbond = SEI_STAKING_CONTRACT.getUnbondingDelegation(validator, unlockID);
        // TODO: check unbonding time denomination
        if (unbond.completionTime > block.timestamp) {
            revert WithdrawPendingError();
        }
        amount = unbond.amount;
    }

    function rebase(address validator, uint256 /*currentStake*/ ) external override returns (uint256 newStake) {
        Storage storage $ = _loadStorage();
        if ($.validator == address(0)) $.validator = validator;

        uint256 shares = SEI_STAKING_CONTRACT.getDelegation(address(this), validator);
        StakingPool memory stakingPool = SEI_STAKING_CONTRACT.getStakingPool(validator);
        newStake = shares.mulDivDown(stakingPool.totalTokens, stakingPool.totalShares);
    }

    function _previewDeposit(address validator, uint256 assets) internal view returns (uint256 out) {
        StakingPool memory stakingPool = SEI_STAKING_CONTRACT.getStakingPool(validator);
        uint256 shares = assets.mulDivDown(stakingPool.totalShares, stakingPool.totalTokens);
        return shares.mulDivDown(stakingPool.totalTokens + assets, stakingPool.totalShares + shares);
    }
}
