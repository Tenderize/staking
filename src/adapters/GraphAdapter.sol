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

pragma solidity 0.8.17;

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { Adapter } from "core/adapters/Adapter.sol";
import { IGraphStaking } from "core/adapters/interfaces/IGraph.sol";

contract GraphAdapter is Adapter {
    using SafeTransferLib for ERC20;

    IGraphStaking private constant GRAPH = IGraphStaking(0xF55041E37E12cD407ad00CE2910B8269B01263b9);
    ERC20 private constant GRT = ERC20(0xc944E90C64B2c07662A292be6244BDf05Cda44a7);
    uint256 private constant MAX_PPM = 1e6;

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.graph.withdrawals.storage.location")) - 1;

    error WithdrawPending();

    struct Unlock {
        uint256 shares;
        uint256 epoch;
    }

    struct Epoch {
        uint256 amount;
        uint256 totalShares;
    }

    struct Storage {
        uint256 lastUnlockID;
        uint256 currentEpoch;
        uint256 lastEpochUnlockedAt;
        mapping(uint256 => Epoch) epochs;
        mapping(uint256 => Unlock) unlocks;
        uint256 tokensPerShare;
    }

    function _loadStorage() internal pure returns (Storage storage s) {
        uint256 slot = STORAGE;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return assets - assets * GRAPH.delegationTaxPercentage() / MAX_PPM;
    }

    function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
        Storage storage $ = _loadStorage();
        Unlock memory unlock = $.unlocks[unlockID];
        Epoch memory epoch = $.epochs[unlock.epoch];
        return unlock.shares * epoch.amount / epoch.totalShares;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        Storage storage $ = _loadStorage();
        Unlock memory unlock = $.unlocks[unlockID];
        uint256 THAWING_PERIOD = GRAPH.thawingPeriod();
        // if userEpoch == currentEpoch, it is yet to unlock
        // => unlockTime + thawingPeriod
        // if userEpoch == currentEpoch - 1, it is processing
        // => unlockTime
        // if userEpoch < currentEpoch - 1, it has been processed
        // => 0
        uint256 tokensLockedUntil = $.lastEpochUnlockedAt + THAWING_PERIOD;
        if (unlock.epoch == $.currentEpoch) {
            return THAWING_PERIOD + tokensLockedUntil;
        } else if (unlock.epoch == $.currentEpoch - 1) {
            return tokensLockedUntil;
        } else {
            return 0;
        }
    }

    function stake(address validator, uint256 amount) external override {
        GRT.safeApprove(address(GRAPH), amount);
        GRAPH.delegate(validator, amount);
    }

    function unstake(address validator, uint256 amount) external override returns (uint256 unlockID) {
        Storage storage $ = _loadStorage();
        Epoch memory e = $.epochs[$.currentEpoch];

        uint256 shares = e.amount == 0 ? amount : amount * e.totalShares / e.amount;

        e.amount += amount;
        e.totalShares += shares;
        $.epochs[$.currentEpoch] = e;

        unlockID = ++$.lastUnlockID;
        $.unlocks[unlockID] = Unlock({ shares: shares, epoch: $.currentEpoch });

        _processWithdrawals(validator);
    }

    function withdraw(address validator, uint256 unlockID) external override returns (uint256 amount) {
        _processWithdrawals(validator);
        Storage storage $ = _loadStorage();
        Unlock memory unlock = $.unlocks[unlockID];
        Epoch memory epoch = $.epochs[unlock.epoch];

        if (unlock.epoch >= $.currentEpoch - 1) revert WithdrawPending();

        if (unlock.shares == epoch.totalShares) {
            amount = epoch.amount;
            delete $.epochs[unlock.epoch];
        } else {
            amount = unlock.shares * epoch.amount / epoch.totalShares;
            epoch.amount -= amount;
            epoch.totalShares -= unlock.shares;
            $.epochs[unlock.epoch] = epoch;
        }

        delete $.unlocks[unlockID];
    }

    function claimRewards(address validator, uint256 currentStake) external override returns (uint256 newStake) {
        Storage storage $ = _loadStorage();
        Epoch memory currentEpoch = $.epochs[$.currentEpoch];
        IGraphStaking.DelegationPool memory delPool = GRAPH.delegationPools(validator);

        uint256 _tokensPerShare = delPool.tokens * 1 ether / delPool.shares;
        // Account for rounding error of -1 or +1
        // This occurs due to a slight change in ratio because of new delegations or withdrawals,
        // rather than an effective reward or loss
        if (
            (_tokensPerShare >= $.tokensPerShare && _tokensPerShare - $.tokensPerShare <= 1)
                || (_tokensPerShare < $.tokensPerShare && $.tokensPerShare - _tokensPerShare <= 1)
        ) {
            return currentStake;
        }

        IGraphStaking.Delegation memory delegation = GRAPH.getDelegation(validator, address(this));
        uint256 staked = delegation.shares * _tokensPerShare / 1 ether;

        // account for stake still to unstake
        uint256 oldStake = currentStake + currentEpoch.amount;

        // Last epoch amount should be synced with Delegation.tokensLocked
        if ($.currentEpoch > 0) $.epochs[$.currentEpoch - 1].amount = delegation.tokensLocked;

        if (staked < oldStake) {
            // handle a potential slash
            // A slash needs to be distributed accross 2 parts
            // - Stake still to unlock (current Unlocks epoch)
            // - Current Staked amount (total supply)
            uint256 slash = oldStake - staked;

            // Slash for the current epoch slashCurrent is calculated as
            // slashCurrent = (slash - slashLast) * currentEpochAmount / ( currentEpochAmount + currentStake)
            uint256 slashCurrent = slash * currentEpoch.amount / oldStake;
            currentEpoch.amount -= slashCurrent;
        } else if (staked > oldStake) {
            // handle rewards
            // To reduce long waiting periods we want to still reward users
            // for which their stake is still to be unlocked
            // because technically it is not unlocked from the Graph either
            // We do this by adding the rewards to the current epoch
            uint256 currentEpochAmount = (staked - oldStake) * currentEpoch.amount / oldStake;
            currentEpoch.amount += currentEpochAmount;
        }

        $.epochs[$.currentEpoch] = currentEpoch;
        $.tokensPerShare = _tokensPerShare == 0 ? 1 ether : _tokensPerShare;

        // slash/rewards is already accounted for in $.epochs[$.currentEpoch].amount
        newStake = staked - currentEpoch.amount;
    }

    function isValidator(address validator) public view override returns (bool) {
        return GRAPH.hasStake(validator);
    }

    function _processWithdrawals(address validator) internal {
        // process possible withdrawals before unstakes
        _processWithdraw(validator);
        _processUnstake(validator);
    }

    function _processUnstake(address validator) internal {
        IGraphStaking.Delegation memory del = GRAPH.getDelegation(validator, address(this));
        // undelegation already ungoing: no-op
        if (del.tokensLockedUntil != 0) return;

        Storage storage $ = _loadStorage();
        uint256 currentEpochAmount = $.epochs[$.currentEpoch].amount;

        // if current epoch amount is non-zero
        // => progress epoch and undelegate from underlying
        // if current epoch is zero and previous epoch is non-zero
        // => only progress epoch, as withdrawal of last epoch is processed
        // => would return at del.tokensLockedUntil check if withdrawal is yet to process
        // if current and previous epoch are zero
        // => no-op - optimization, no need to progress epochs if last two are emtpy
        // => ie. no pending unlocks, no unlocks processing
        if (currentEpochAmount != 0) {
            ++$.currentEpoch;
            $.lastEpochUnlockedAt = block.number;

            // calculate shares to undelegate from The Graph
            uint256 undelegationShares = currentEpochAmount * 1 ether / $.tokensPerShare;

            // account for possible rounding error
            undelegationShares = del.shares < undelegationShares ? del.shares : undelegationShares;

            // undelegate
            GRAPH.undelegate(validator, undelegationShares);
        } else if ($.epochs[$.currentEpoch - 1].amount != 0) {
            ++$.currentEpoch;
            $.lastEpochUnlockedAt = block.number;
        }
    }

    function _processWithdraw(address validator) internal {
        // withdrawal isn't ready: no-op
        uint256 tokensLockedUntil = GRAPH.getDelegation(validator, address(this)).tokensLockedUntil;
        if (tokensLockedUntil == 0 || tokensLockedUntil > block.number) return;

        Storage storage $ = _loadStorage();

        // withdraw undelegated
        unchecked {
            // $.currentEpoch - 1 is safe as we only call this function after at least 1 _processUnstake
            // which increments $.currentEpoch, otherwise del.tokensLockedUntil would still be 0 and we would
            // not reach this branch
            $.epochs[$.currentEpoch - 1].amount = GRAPH.withdrawDelegated(validator, address(0));
        }
    }
}
