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
    uint256 private constant MAX_PPM = 1_000_000;

    uint256 private constant UNLOCKS_SLOT = uint256(keccak256("xyz.tenderize.graph.withdrawals.storage.location")) - 1;

    error WithdrawPending();

    struct Unlock {
        uint256 shares;
        uint256 epoch;
    }

    struct Epoch {
        uint256 amount;
        uint256 totalShares;
    }

    struct Unlocks {
        uint256 lastUnlockID;
        uint256 currentEpoch;
        uint256 lastEpochUnlockedAt;
        mapping(uint256 => Epoch) epochs;
        mapping(uint256 => Unlock) unlocks;
    }

    function _loadUnlocksSlot() internal pure returns (Unlocks storage s) {
        uint256 slot = UNLOCKS_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }

    function previewDeposit(uint256 assets) external view override returns (uint256) {
        return assets - assets * GRAPH.delegationTaxPercentage() / MAX_PPM;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        Unlocks storage u = _loadUnlocksSlot();
        Unlock memory unlock = u.unlocks[unlockID];
        // if userEpoch == currentEpoch, it is yet to unlock
        // => unlockTime + thawingPeriod
        // if userEpoch == currentEpoch - 1, it is processing
        // => unlockTime
        // if userEpoch < currentEpoch - 1, it has been processed
        // => 0
        uint256 tokensLockedUntil = u.lastEpochUnlockedAt + GRAPH.thawingPeriod();
        if (unlock.epoch == u.currentEpoch) {
            return GRAPH.thawingPeriod() + tokensLockedUntil;
        } else if (unlock.epoch == u.currentEpoch - 1) {
            return tokensLockedUntil;
        } else {
            return 0;
        }
    }

    function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
        Unlocks storage u = _loadUnlocksSlot();
        Unlock memory unlock = u.unlocks[unlockID];
        Epoch memory epoch = u.epochs[unlock.epoch];
        return unlock.shares * epoch.amount / epoch.totalShares;
    }

    function getTotalStaked(address validator) external view override returns (uint256) {
        IGraphStaking.Delegation memory delegation = GRAPH.getDelegation(validator, msg.sender);
        IGraphStaking.DelegationPool memory delPool = GRAPH.delegationPools(validator);

        uint256 delShares = delegation.shares;
        uint256 totalShares = delPool.shares;
        uint256 totalTokens = delPool.tokens;

        if (totalShares == 0) return 0;

        return delShares * totalTokens / totalShares;
    }

    function stake(address validator, uint256 amount) external override {
        GRT.safeApprove(address(GRAPH), amount);
        GRAPH.delegate(validator, amount);
    }

    function unstake(address validator, uint256 amount) external override returns (uint256 unlockID) {
        Unlocks storage u = _loadUnlocksSlot();
        Epoch storage e = u.epochs[u.currentEpoch];

        uint256 shares = e.amount == 0 ? amount : amount * e.totalShares / e.amount;

        e.amount += amount;
        e.totalShares += shares;
        unlockID = ++u.lastUnlockID;
        u.unlocks[unlockID] = Unlock({ shares: shares, epoch: u.currentEpoch });

        _processWithdrawals(validator);
    }

    function withdraw(address validator, uint256 unlockID) external override returns (uint256 amount) {
        _processWithdrawals(validator);
        Unlocks storage u = _loadUnlocksSlot();
        Unlock memory unlock = u.unlocks[unlockID];
        Epoch storage epoch = u.epochs[unlock.epoch];

        if (unlock.epoch >= u.currentEpoch - 1) revert WithdrawPending();

        if (unlock.shares == epoch.totalShares) {
            amount = epoch.amount;
            delete u.epochs[unlock.epoch];
        } else {
            amount = unlock.shares * epoch.amount / epoch.totalShares;
            epoch.amount -= amount;
            epoch.totalShares -= unlock.shares;
        }

        delete u.unlocks[unlockID];
    }

    function claimRewards(address validator, uint256 currentStake) external override returns (uint256 newStake) {
        Unlocks storage u = _loadUnlocksSlot();
        // TODO: Change to use totalStaked() after https://github.com/Tenderize/staking/issues/20
        IGraphStaking.Delegation memory delegation = GRAPH.getDelegation(validator, address(this));
        IGraphStaking.DelegationPool memory delPool = GRAPH.delegationPools(validator);
        uint256 staked = delegation.shares * delPool.tokens / delPool.shares;

        // account for stake still to unstake
        uint256 oldStake = currentStake + u.epochs[u.currentEpoch].amount;

        // Last epoch amount should be synced with Delegation.tokensLocked
        if (u.currentEpoch > 0) u.epochs[u.currentEpoch - 1].amount = delegation.tokensLocked;

        if (staked < oldStake) {
            // handle a potential slash
            // A slash needs to be distributed accross 2 parts
            // - Stake still to unlock (current Unlocks epoch)
            // - Current Staked amount (total supply)
            uint256 slash = oldStake - staked;

            // Slash for the current epoch slashCurrent is calculated as
            // slashCurrent = (slash - slashLast) * currentEpochAmount / ( currentEpochAmount + currentStake)
            uint256 slashCurrent = slash * u.epochs[u.currentEpoch].amount / oldStake;
            u.epochs[u.currentEpoch].amount -= slashCurrent;
        } else if (staked > oldStake) {
            // handle rewards
            // To reduce long waiting periods we want to still reward users
            // for which their stake is still to be unlocked
            // because technically it is not unlocked from the Graph either
            // We do this by adding the rewards to the current epoch
            uint256 currentEpochAmount = (staked - oldStake) * u.epochs[u.currentEpoch].amount / oldStake;
            u.epochs[u.currentEpoch].amount += currentEpochAmount;
        }

        // slash/rewards is already accounted for in u.epochs[u.currentEpoch].amount
        newStake = staked - u.epochs[u.currentEpoch].amount;
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

        Unlocks storage u = _loadUnlocksSlot();
        Epoch storage e = u.epochs[u.currentEpoch];

        // if current epoch amount is non-zero
        // => progress epoch and undelegate from underlying
        // if current epoch is zero and previous epoch is non-zero
        // => only progress epoch, as withdrawal of last epoch is processed
        // => would return at del.tokensLockedUntil check if withdrawal is yet to process
        // if current and previous epoch are zero
        // => no-op - optimization, no need to progress epochs if last two are emtpy
        // => ie. no pending unlocks, no unlocks processing
        if (e.amount != 0) {
            ++u.currentEpoch;
            u.lastEpochUnlockedAt = block.number;

            // calculate shares to undelegate from The Graph
            IGraphStaking.DelegationPool memory delPool = GRAPH.delegationPools(validator);
            uint256 undelegationShares = e.amount * delPool.shares / delPool.tokens;

            // account for possible rounding error
            undelegationShares = del.shares < undelegationShares ? del.shares : undelegationShares;

            // undelegate
            GRAPH.undelegate(validator, undelegationShares);
        } else if (u.epochs[u.currentEpoch - 1].amount != 0) {
            ++u.currentEpoch;
            u.lastEpochUnlockedAt = block.number;
        }
    }

    function _processWithdraw(address validator) internal {
        // withdrawal isn't ready: no-op
        IGraphStaking.Delegation memory del = GRAPH.getDelegation(validator, address(this));
        if (del.tokensLockedUntil == 0 || del.tokensLockedUntil > block.number) return;

        Unlocks storage u = _loadUnlocksSlot();

        // withdraw undelegated
        unchecked {
            // u.currentEpoch - 1 is safe as we only call this function after at least 1 _processUnstake
            // which increments u.currentEpoch, otherwise del.tokensLockedUntil would still be 0 and we would
            // not reach this branch
            u.epochs[u.currentEpoch - 1].amount = GRAPH.withdrawDelegated(validator, address(0));
        }
    }
}
