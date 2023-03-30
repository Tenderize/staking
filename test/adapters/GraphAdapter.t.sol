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

import { Test, stdError } from "forge-std/Test.sol";
import { GraphAdapter } from "core/adapters/GraphAdapter.sol";
import { IERC20 } from "core/interfaces/IERC20.sol";
import { IGraphStaking } from "core/adapters/interfaces/IGraph.sol";
import { TestHelpers } from "test/helpers/Helpers.sol";

// solhint-disable func-name-mixedcase

contract GraphAdapterTest is Test, GraphAdapter, TestHelpers {
    address private staking = 0xF55041E37E12cD407ad00CE2910B8269B01263b9;
    address private token = 0xc944E90C64B2c07662A292be6244BDf05Cda44a7;

    address private validator = vm.addr(1);

    uint256 private constant DELEGATION_TAX = 5000;
    uint256 private constant MAX_PPM = 1_000_000;
    uint256 private constant THAWING_PERIOD = 201_600;

    uint256 private constant MAX_UINT = type(uint256).max;
    uint256 private MAX_UINT_SQRT = sqrt(MAX_UINT - 1);

    function setUp() public {
        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.delegationTaxPercentage.selector), abi.encode(DELEGATION_TAX));
        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.thawingPeriod.selector), abi.encode(THAWING_PERIOD));
    }

    function testFuzz_PreviewDeposit(uint256 amount) public {
        amount = bound(amount, 0, MAX_UINT / DELEGATION_TAX);
        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.delegationTaxPercentage.selector));
        assertEq(this.previewDeposit(amount), amount - amount * DELEGATION_TAX / MAX_PPM);
    }

    function testFuzz_UnlockMaturity(uint256 lastEpochUnlockedAt, uint256 userEpoch) public {
        uint256 unlockId = 1;
        uint256 currentEpoch = 2;
        userEpoch = bound(userEpoch, 0, currentEpoch);
        vm.roll(rand(1, 1, 1, MAX_UINT_SQRT));

        lastEpochUnlockedAt = bound(lastEpochUnlockedAt, block.number - THAWING_PERIOD, block.number);

        Unlocks storage u = _loadUnlocksSlot();
        u.currentEpoch = currentEpoch;
        u.unlocks[unlockId].epoch = userEpoch;
        u.lastEpochUnlockedAt = lastEpochUnlockedAt;

        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.thawingPeriod.selector));

        if (userEpoch == currentEpoch) {
            assertEq(this.unlockMaturity(unlockId), u.lastEpochUnlockedAt + 2 * THAWING_PERIOD, "invalid when yet to process");
        }
        if (userEpoch == currentEpoch - 1) {
            assertEq(this.unlockMaturity(unlockId), u.lastEpochUnlockedAt + THAWING_PERIOD, "invalid when processing");
        }
        if (userEpoch < currentEpoch - 1) assertEq(this.unlockMaturity(unlockId), 0, "invalid when processed");
    }

    function testFuzz_PreviewWithdraw(uint256 unlockShares, uint256 epochAmount, uint256 epochTotalShares) public {
        uint256 unlockID = 1;
        uint256 unlockEpoch = 1;
        vm.assume(epochTotalShares > 0);
        unlockShares = bound(unlockShares, 0, MAX_UINT_SQRT);
        epochAmount = bound(epochAmount, 0, MAX_UINT_SQRT);
        Unlocks storage u = _loadUnlocksSlot();
        u.unlocks[unlockID].shares = unlockShares;
        u.unlocks[unlockID].epoch = unlockEpoch;
        u.epochs[unlockEpoch].amount = epochAmount;
        u.epochs[unlockEpoch].totalShares = epochTotalShares;
        assertEq(this.previewWithdraw(unlockID), unlockShares * epochAmount / epochTotalShares);
    }

    function testFuzz_GetTotalStaked(uint256 shares, uint256 totalShares, uint256 totalTokens) public {
        shares = bound(shares, 0, MAX_UINT_SQRT);
        totalTokens = bound(totalTokens, 0, MAX_UINT_SQRT);
        totalShares = bound(totalShares, 0, MAX_UINT_SQRT);

        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(shares, 0, 0)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, totalTokens, totalShares)
        );
        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)));
        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator));
        uint256 exp = totalShares == 0 ? 0 : shares * totalTokens / totalShares;
        assertEq(this.getTotalStaked(validator), exp);
    }

    function test_Stake() public {
        uint256 amount = 1 ether;
        vm.mockCall(token, abi.encodeWithSelector(IERC20.approve.selector, staking, amount), abi.encode(true));
        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.delegate.selector, validator, amount), abi.encode(amount));
        vm.expectCall(token, abi.encodeWithSelector(IERC20.approve.selector, staking, amount));
        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.delegate.selector, validator, amount));
        this.stake(validator, amount);
    }

    function test_Stake_RevertIfApproveFails() public {
        vm.mockCall(token, abi.encodeWithSelector(IERC20.approve.selector), abi.encode(false));
        vm.expectRevert("APPROVE_FAILED");
        this.stake(validator, 1 ether);
    }

    function testFuzz_Unstake_WithoutProcessing(uint256 amount, uint256 epochAmount, uint256 epochShares) public {
        vm.roll(1);
        uint256 epoch = 1;
        uint256 lastUnlockID = 0;

        amount = bound(amount, 1, MAX_UINT_SQRT);
        epochShares = bound(epochShares, 0, MAX_UINT_SQRT);
        epochAmount = bound(epochAmount, 0, MAX_UINT_SQRT);

        // prevent unlock processing by setting the mocked value for `Delegation.tokensLockedUntil` to `block.number + 1`
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(10 ether, 1 ether, block.number + 1)
        );

        Unlocks storage u = _loadUnlocksSlot();
        u.currentEpoch = epoch;
        u.epochs[epoch].amount = epochAmount;
        u.epochs[epoch].totalShares = epochShares;
        u.lastUnlockID = lastUnlockID;

        uint256 unlockID = this.unstake(validator, amount);

        uint256 expShares = epochAmount == 0 ? amount : amount * epochShares / epochAmount;
        assertEq(unlockID, lastUnlockID + 1, "invalid unlock ID returned");
        assertEq(u.epochs[epoch].amount, epochAmount + amount, "invalid epoch amount");
        assertEq(u.epochs[epoch].totalShares, epochShares + expShares, "invalid epoch shares");
        assertEq(u.unlocks[unlockID].shares, expShares, "invalid unlock shrares");
        assertEq(u.unlocks[unlockID].epoch, 1, "invalid unlock epoch");
        assertEq(u.lastUnlockID, lastUnlockID + 1, "invalid nextUnlockID");
        assertEq(u.currentEpoch, epoch, "invalid epoch");
    }

    function testFuzz_Unstake(uint256 currentEpochAmount, uint256 stakedAmount, uint256 stakedShares) public {
        uint256 amount = 1 ether;
        currentEpochAmount = bound(currentEpochAmount, 1, MAX_UINT_SQRT - amount);
        stakedAmount = bound(stakedAmount, 1, MAX_UINT_SQRT);
        stakedShares = bound(stakedShares, 1, MAX_UINT_SQRT);
        uint256 epoch = 1;
        uint256 lastUnlockID = 1;

        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(stakedShares, 0, 0)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, stakedAmount, stakedShares)
        );

        uint256 expShares = (currentEpochAmount + amount) * stakedShares / stakedAmount;
        expShares = expShares > stakedShares ? stakedShares : expShares;
        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.undelegate.selector, validator, expShares), abi.encode(expShares));

        Unlocks storage u = _loadUnlocksSlot();
        u.currentEpoch = epoch;
        u.epochs[epoch].amount = currentEpochAmount;
        u.epochs[epoch].totalShares = currentEpochAmount;
        u.lastUnlockID = lastUnlockID;

        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.undelegate.selector, validator, expShares));
        this.unstake(validator, amount);
        assertEq(u.currentEpoch, epoch + 1, "invalid epoch");
        assertEq(u.lastEpochUnlockedAt, block.number, "invalid lastEpochUnlockedAt");
        assertEq(u.unlocks[lastUnlockID + 1].shares, amount, "invalid unlock shares");
        assertEq(u.unlocks[lastUnlockID + 1].epoch, epoch, "invalid unlock epoch");
        assertEq(u.epochs[epoch].amount, currentEpochAmount + amount, "invalid epoch amount");
        assertEq(u.epochs[epoch].totalShares, currentEpochAmount + amount, "invalid epoch shares");
    }

    function test_Withdraw_LastTwoEpochsEmpty() public {
        uint256 amount = 1 ether;
        // should neither call `undelegate` nor `withdrawDelegation`
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(amount, 0, 0)
        );

        Unlocks storage u = _loadUnlocksSlot();
        uint256 epoch = 2;
        u.currentEpoch = epoch;
        this.withdraw(validator, 0);
        assertEq(u.currentEpoch, epoch, "invalid epoch");
        assertEq(u.lastEpochUnlockedAt, 0, "invalid lastEpochUnlockedAt");
    }

    function test_Withdraw_PreviousEpochEmpty() public {
        uint256 amount = 1 ether;

        // should call `undelegate` but not `withdrawDelegation`
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(amount, 0, 0)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, amount, amount)
        );

        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.undelegate.selector, validator, amount), abi.encode(0));

        Unlocks storage u = _loadUnlocksSlot();
        // set unlock id 0 for epoch 0
        u.unlocks[0].shares = amount;
        u.epochs[0].totalShares = amount;
        u.epochs[0].amount = amount;

        uint256 epoch = 2;
        u.currentEpoch = epoch;
        u.epochs[epoch].amount = amount;
        u.epochs[epoch].totalShares = amount;

        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.undelegate.selector, validator, amount));
        this.withdraw(validator, 0);
        assertEq(u.currentEpoch, epoch + 1, "invalid epoch");
        assertEq(u.lastEpochUnlockedAt, block.number, "invalid lastEpochUnlockedAt");
        assertEq(u.epochs[0].amount, 0, "invalid unlock epoch amount");
        assertEq(u.epochs[0].totalShares, 0, "invalid unlock epoch shares");
        assertEq(u.epochs[epoch - 1].amount, 0, "invalid previous epoch amount");
    }

    function test_ProcessWithdraw() public {
        uint256 amount = 1 ether;

        uint256 tokensLocked = 1 ether;
        uint256 currentBlock = 100;
        vm.roll(currentBlock);
        uint256 tokensLockedUntil = rand(1, 1, 0, currentBlock - 1);
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(10 ether, tokensLocked, tokensLockedUntil)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, 10 ether, 10 ether)
        );

        vm.mockCall(staking, abi.encodeWithSelector(IGraphStaking.undelegate.selector, validator, amount), abi.encode(0));

        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.withdrawDelegated.selector, validator, address(0)),
            abi.encode(tokensLocked)
        );

        uint256 epoch = 1;
        _loadUnlocksSlot().currentEpoch = epoch;

        vm.expectCall(staking, abi.encodeWithSelector(IGraphStaking.withdrawDelegated.selector, validator, address(0)));
        uint256 unlockID = this.unstake(validator, amount);

        Unlocks storage u = _loadUnlocksSlot();

        assertEq(u.currentEpoch, epoch, "invalid epoch");
        assertEq(u.unlocks[unlockID].shares, amount, "invalid unlock shares");
        assertEq(u.unlocks[unlockID].epoch, epoch, "invalid unlock epoch");
        assertEq(u.epochs[epoch].amount, amount, "invalid epoch amount");
        assertEq(u.epochs[epoch].totalShares, amount, "invalid epoch shares");
    }

    function testFuzz_Withdraw_WithoutProcessing(uint256 unlockShares, uint256 epochAmount, uint256 epochShares) public {
        uint256 unlockID = 1;
        uint256 unlockEpoch = 10;
        epochShares = bound(epochShares, 1, MAX_UINT_SQRT);
        unlockShares = bound(unlockShares, 1, epochShares);
        epochAmount = bound(epochAmount, 1, MAX_UINT_SQRT);

        // unlock processing
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(10 ether, 1 ether, block.number + 1)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, 10 ether, 10 ether)
        );

        Unlocks storage u = _loadUnlocksSlot();
        u.unlocks[unlockID].epoch = unlockEpoch;
        u.currentEpoch = unlockEpoch + 2;
        u.unlocks[unlockID].shares = unlockShares;
        u.epochs[unlockEpoch].totalShares = epochShares;
        u.epochs[unlockEpoch].amount = epochAmount;

        uint256 returnedAmount = this.withdraw(validator, unlockID);

        uint256 expAmount = unlockShares * epochAmount / epochShares;
        assertEq(returnedAmount, expAmount, "invalid return value");
        assertEq(u.epochs[unlockEpoch].totalShares, epochShares - unlockShares, "invalid epoch shares");
        assertEq(u.epochs[unlockEpoch].amount, epochAmount - expAmount, "invalid epoch shares");
        assertEq(u.unlocks[unlockID].epoch, 0, "unlock not deleted");
        assertEq(u.unlocks[unlockID].shares, 0, "unlock not deleted");

        if (u.epochs[unlockEpoch].amount == 0) {
            assertEq(u.epochs[unlockEpoch].totalShares, 0, "epoch not deleted");
        }
    }

    function test_Withdraw_RevertIfPending() public {
        uint256 unlockID = 1;
        uint256 currnetEpoch = 100;
        uint256 unlockEpoch = 101;

        // unlock processing
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(10 ether, 1 ether, block.number + 1)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, 10 ether, 10 ether)
        );

        Unlocks storage u = _loadUnlocksSlot();
        u.unlocks[unlockID].epoch = unlockEpoch;
        u.currentEpoch = currnetEpoch;

        vm.expectRevert(WithdrawPending.selector);
        this.withdraw(validator, unlockID);
    }

    function testFuzz_claimRewards_Positive(uint256 startStake, uint256 reward) public {
        startStake = bound(startStake, 1, MAX_UINT_SQRT);
        reward = bound(reward, 1, MAX_UINT_SQRT);

        // percentage of startStake that is epochs[currentEpoch].amount
        uint256 currentEpochRatio = 0.33 ether;
        uint256 currentEpochAmountStart = startStake * currentEpochRatio / 1 ether;

        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)),
            abi.encode(1, 1 ether, 0)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, startStake + reward, 1)
        );

        Unlocks storage u = _loadUnlocksSlot();
        uint256 currentEpoch = 1;
        u.currentEpoch = currentEpoch;
        u.epochs[currentEpoch].amount = currentEpochAmountStart;

        uint256 newStake = this.claimRewards(validator, startStake - currentEpochAmountStart);

        uint256 rewardForUnlocks = reward * currentEpochAmountStart / startStake;
        uint256 rewardForStake = reward - rewardForUnlocks;
        assertEq(newStake, startStake + rewardForStake - currentEpochAmountStart, "invalid new stake");
        assertEq(u.epochs[currentEpoch].amount, currentEpochAmountStart + rewardForUnlocks, "invalid current epoch amount");
        assertEq(u.epochs[currentEpoch - 1].amount, 1 ether, "invalid previous epoch amount");
    }

    function testFuzz_claimRewards_Negative(uint256 startStake, uint256 penalty) public {
        startStake = bound(startStake, 1, MAX_UINT_SQRT);
        penalty = bound(penalty, 1, startStake);

        // percentage of startStake that is epochs[currentEpoch].amount
        uint256 currentEpochRatio = 0.33 ether;
        uint256 currentEpochAmountStart = startStake * currentEpochRatio / 1 ether;

        vm.mockCall(
            staking, abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)), abi.encode(1, 0, 0)
        );
        vm.mockCall(
            staking,
            abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator),
            abi.encode(0, 0, 0, 0, startStake - penalty, 1)
        );

        Unlocks storage u = _loadUnlocksSlot();
        uint256 currentEpoch = 1;
        u.currentEpoch = currentEpoch;
        u.epochs[currentEpoch].amount = currentEpochAmountStart;

        uint256 newStake = this.claimRewards(validator, startStake - currentEpochAmountStart);
        uint256 slashForUnlocks = penalty * currentEpochAmountStart / startStake;
        assertEq(newStake, startStake - penalty - u.epochs[currentEpoch].amount, "invalid new stake");
        assertEq(u.epochs[currentEpoch].amount, currentEpochAmountStart - slashForUnlocks, "invalid current epoch amount");
    }

    function test_ClaimRewards_NoChangeInStake() public {
        uint256 currentEpoch = 1;
        uint256 staked = 10 ether;
        uint256 currentEpochRatio = 0.33 ether;
        uint256 currentEpochAmount = staked * currentEpochRatio / 1 ether;

        vm.mockCall(
            staking, abi.encodeWithSelector(IGraphStaking.getDelegation.selector, validator, address(this)), abi.encode(1, 0, 0)
        );
        vm.mockCall(
            staking, abi.encodeWithSelector(IGraphStaking.delegationPools.selector, validator), abi.encode(0, 0, 0, 0, staked, 1)
        );

        Unlocks storage u = _loadUnlocksSlot();
        u.currentEpoch = currentEpoch;
        u.epochs[currentEpoch].amount = currentEpochAmount;

        uint256 newStake = this.claimRewards(validator, staked - currentEpochAmount);
        assertEq(newStake, staked - currentEpochAmount, "invalid new stake");
    }
}
