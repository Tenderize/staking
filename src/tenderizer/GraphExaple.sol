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
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { Adapter } from "core/tenderizer/Adapter.sol";

pragma solidity 0.8.17;

interface IGraphStaking {
  // -- Delegation Data --

  /**
   * @dev Delegation pool information. One per indexer.
   */
  struct DelegationPool {
    uint32 cooldownBlocks; // Blocks to wait before updating parameters
    uint32 indexingRewardCut; // in PPM
    uint32 queryFeeCut; // in PPM
    uint256 updatedAtBlock; // Block when the pool was last updated
    uint256 tokens; // Total tokens as pool reserves
    uint256 shares; // Total shares minted in the pool
    // mapping(address => Delegation) delegators; // Mapping of delegator => Delegation
  }

  /**
   * @dev Individual delegation data of a delegator in a pool.
   */
  struct Delegation {
    uint256 shares; // Shares owned by a delegator in the pool
    uint256 tokensLocked; // Tokens locked for undelegation
    uint256 tokensLockedUntil; // Block when locked tokens can be withdrawn
  }

  function delegate(address _indexer, uint256 _tokens) external returns (uint256);

  function undelegate(address _indexer, uint256 _shares) external returns (uint256);

  function withdrawDelegated(address _indexer, address _newIndexer) external returns (uint256);

  function getDelegation(address _indexer, address _delegator) external view returns (Delegation memory);

  function delegationPools(address _indexer) external view returns (DelegationPool memory);

  function getWithdraweableDelegatedTokens(Delegation memory _delegation) external view returns (uint256);

  function thawingPeriod() external view returns (uint256);

  function delegationTaxPercentage() external view returns (uint32);
}

contract GraphAdapter is Adapter {
  using SafeTransferLib for ERC20;
  IGraphStaking graph;
  ERC20 GRT;

  error WithdrawPending();

  uint256 private constant WITHDRAWALS_SLOT =
    uint256(keccak256("xyz.tenderize.graph.withdrawals.storage.location")) - 1;

  uint256 constant MAX_PPM = 1000000;

  struct Withdrawal {
    uint256 shares;
    uint256 epoch;
  }

  struct Withdrawals {
    uint256 toUnlock;
    uint256 unlocked;
    uint256 withdrawable;
    uint256 totalShares;
    uint256 nextUnlockID;
    uint256 currentEpoch;
    uint256 lastEpoch;
    mapping(uint256 => Withdrawal) unlocks; // unlockID => Withdrawal
  }

  function _loadWithdrawalsSlot() internal pure returns (Withdrawals storage s) {
    uint256 slot = WITHDRAWALS_SLOT;

    // solhint-disable-next-line no-inline-assembly
    assembly {
      s.slot := slot
    }
  }

  function previewDeposit(uint256 assets) external view override returns (uint256) {
    return (assets * (MAX_PPM - graph.delegationTaxPercentage())) / MAX_PPM;
  }

  function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
    Withdrawals storage w = _loadWithdrawalsSlot();
    Withdrawal memory withdrawal = w.unlocks[unlockID];
    // current epoch is time of last unlock
    // if user epoch == current epoch it is still to unlock
    // => thawingPeriod + unlockTime - currentEpoch
    // if user epoch < current epoch it is unlocking
    // => unlocktime
    // if user epoch < last epoch it is unlocked
    // => 0
    uint256 tokensLockedUntil = w.currentEpoch + graph.thawingPeriod();
    if (withdrawal.epoch == w.currentEpoch) {
      return block.number + graph.thawingPeriod() + tokensLockedUntil - block.number;
    } else if (withdrawal.epoch < w.currentEpoch) {
      return tokensLockedUntil;
    } else {
      return 0;
    }
  }

  function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
    Withdrawals storage w = _loadWithdrawalsSlot();
    return (w.unlocks[unlockID].shares * (w.toUnlock + w.withdrawable + w.unlocked)) / w.totalShares;
  }

  function getTotalStaked(address validator) external view override returns (uint256) {
    IGraphStaking.Delegation memory delegation = graph.getDelegation(validator, address(this));
    IGraphStaking.DelegationPool memory delPool = graph.delegationPools(validator);

    uint256 delShares = delegation.shares;
    uint256 totalShares = delPool.shares;
    uint256 totalTokens = delPool.tokens;

    if (totalShares == 0) return 0;

    return (delShares * totalTokens) / totalShares;
  }

  function stake(address validator, uint256 amount) external override {
    GRT.safeApprove(address(graph), amount);
    graph.delegate(validator, amount);
  }

  function unstake(address validator, uint256 amount) external override returns (uint256 unlockID) {
    Withdrawals storage w = _loadWithdrawalsSlot();
    uint256 shares = (amount * w.totalShares) / (w.toUnlock + w.withdrawable + w.unlocked);

    w.toUnlock += amount;
    w.totalShares += shares;
    unlockID = w.nextUnlockID++; // post-increment returns the old value but is a little bit more costly
    w.unlocks[unlockID] = Withdrawal({ shares: shares, epoch: w.currentEpoch });

    _processWithdrawals(validator);
  }

  function withdraw(address validator, uint256 unlockID) external override {
    _processWithdrawals(validator);
    Withdrawals storage w = _loadWithdrawalsSlot();
    Withdrawal memory withdrawal = w.unlocks[unlockID];

    if (withdrawal.epoch < w.lastEpoch) revert WithdrawPending();

    w.withdrawable -= (withdrawal.shares * (w.toUnlock + w.withdrawable + w.unlocked)) / w.totalShares;
    w.totalShares -= withdrawal.shares;
    delete w.unlocks[unlockID];
  }

  function claimRewards() external override {
    // if negative rewards, update tokens to unlock and unlocked
  }

  function _processWithdrawals(address validator) internal {
    // process possible withdrawals before unstakes
    _processWithdraw(validator);
    _processUnstake(validator);
  }

  function _processUnstake(address validator) internal {
    IGraphStaking.Delegation memory del = graph.getDelegation(validator, address(this));
    // undelegation already ungoing: no-op
    if (del.tokensLockedUntil != 0) return;

    Withdrawals storage w = _loadWithdrawalsSlot();

    // calculate shares to undelegate from The Graph
    IGraphStaking.DelegationPool memory delPool = graph.delegationPools(validator);
    uint256 undelegationShares = (w.toUnlock * delPool.shares) / delPool.tokens;
    // account for possible rounding error
    undelegationShares = del.shares < undelegationShares ? del.shares : undelegationShares;

    // update state
    w.toUnlock = 0;
    w.currentEpoch = block.number;

    // undelegate
    graph.undelegate(validator, undelegationShares);
  }

  function _processWithdraw(address validator) internal {
    // withdrawal isn't ready: no-op
    uint256 tokensLockedUntil = graph.getDelegation(validator, address(this)).tokensLockedUntil;
    if (tokensLockedUntil != 0 && tokensLockedUntil > block.number) return;
    Withdrawals storage w = _loadWithdrawalsSlot();
    // update state
    w.withdrawable += w.unlocked;
    w.unlocked = 0;
    w.lastEpoch = w.currentEpoch;

    // withdraw undelegated
    graph.withdrawDelegated(validator, address(0));
  }
}
