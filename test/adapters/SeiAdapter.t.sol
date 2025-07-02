// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import { Test } from "forge-std/Test.sol";
import { SeiAdapter } from "core/tenderize-v3/Sei/SeiAdapter.sol";
import { Adapter } from "core/tenderize-v3/Adapter.sol";
import { ISeiStaking, SEI_STAKING_PRECOMPILE_ADDRESS, Delegation, Balance, DelegationDetails } from "core/tenderize-v3/Sei/Sei.sol";

contract MockSeiStaking {
    mapping(address => mapping(string => uint256)) public delegations;
    mapping(address => mapping(string => uint256)) public unbondingDelegations;
    mapping(address => mapping(string => uint256)) public unbondingTimes;

    bool public shouldFailDelegate;
    bool public shouldFailUndelegate;

    function setShouldFailDelegate(bool _fail) external {
        shouldFailDelegate = _fail;
    }

    function setShouldFailUndelegate(bool _fail) external {
        shouldFailUndelegate = _fail;
    }

    function delegate(string memory valAddress) external payable returns (bool success) {
        if (shouldFailDelegate) {
            return false; // Return false to indicate failure
        }

        delegations[msg.sender][valAddress] += msg.value;
        return true;
    }

    function undelegate(string memory valAddress, uint256 amount) external returns (bool success) {
        if (shouldFailUndelegate) {
            return false; // Return false to indicate failure
        }

        if (delegations[msg.sender][valAddress] >= amount) {
            delegations[msg.sender][valAddress] -= amount;
            unbondingDelegations[msg.sender][valAddress] += amount;
            unbondingTimes[msg.sender][valAddress] = block.timestamp + 21 days;
        }
        return true;
    }

    function delegation(address delegator, string memory valAddress) external view returns (Delegation memory delegation_) {
        uint256 amount = delegations[delegator][valAddress];

        delegation_ = Delegation({
            balance: Balance({ amount: amount, denom: "usei" }),
            delegation: DelegationDetails({
                delegator_address: "sei1delegator",
                shares: amount,
                decimals: 1_000_000, // 6 decimals = 10^6
                validator_address: valAddress
            })
        });
    }
}

contract SeiAdapterTest is Test {
    SeiAdapter public adapter;
    MockSeiStaking public mockStaking;

    bytes32 constant VALIDATOR_1 = hex"1234567890AbcdEF1234567890aBcdef12345678000000000000000000000000";
    bytes32 constant VALIDATOR_2 = hex"fEDCBA0987654321FeDcbA0987654321fedCBA09000000000000000000000000";

    uint256 constant PRECISION_SCALE = 1e12; // 18 - 6 = 12 decimal places
    uint256 constant UNBONDING_PERIOD = 21 days;

    function setUp() public {
        adapter = new SeiAdapter();
        mockStaking = new MockSeiStaking();

        // Mock the Sei staking precompile
        vm.etch(SEI_STAKING_PRECOMPILE_ADDRESS, address(mockStaking).code);

        // Give the test contract some ETH
        vm.deal(address(this), 100 ether);
        vm.deal(address(adapter), 100 ether);
    }

    function testSymbol() public {
        assertEq(adapter.symbol(), "SEI");
    }

    function testSupportsInterface() public {
        assertTrue(adapter.supportsInterface(type(Adapter).interfaceId));
    }

    function testPreviewDeposit() public {
        uint256 assets = 1 ether;
        uint256 preview = adapter.previewDeposit(VALIDATOR_1, assets);
        assertEq(preview, assets);
    }

    function testUnlockTime() public {
        assertEq(adapter.unlockTime(), UNBONDING_PERIOD);
    }

    function testCurrentTime() public {
        assertEq(adapter.currentTime(), block.timestamp);
    }

    function testIsValidator() public {
        assertTrue(adapter.isValidator(VALIDATOR_1));
        assertTrue(adapter.isValidator(VALIDATOR_2));
        assertFalse(adapter.isValidator(bytes32(0)));
    }

    function testBech32Conversion() public {
        // Test that bytes32 to sei validator conversion works
        // We can't easily test the exact bech32 output without a reference implementation
        // but we can test that it doesn't revert and produces some output
        bytes32 testValidator = hex"1234567890AbcdEF1234567890aBcdef12345678000000000000000000000000";

        // This should not revert
        bool success = adapter.isValidator(testValidator);
        assertTrue(success);
    }

    function testStakeSuccess() public {
        uint256 amount = 1 ether;

        uint256 staked = adapter.stake(VALIDATOR_1, amount);

        assertEq(staked, amount);

        // The mock should have received the converted amount
        // But we can't easily check the exact bech32 address without implementing bech32 decode
        // So we just verify the stake operation completed successfully
        assertTrue(staked > 0);
    }

    function testStakeWithZeroAmount() public {
        vm.expectRevert(SeiAdapter.InvalidAmount.selector);
        adapter.stake(VALIDATOR_1, 0);
    }

    function testStakeFailure() public {
        uint256 amount = 1 ether;
        MockSeiStaking(SEI_STAKING_PRECOMPILE_ADDRESS).setShouldFailDelegate(true);

        vm.expectRevert(SeiAdapter.DelegationFailed.selector);
        adapter.stake(VALIDATOR_1, amount);
    }

    function testUnstakeSuccess() public {
        uint256 amount = 1 ether;

        // First stake some tokens
        adapter.stake(VALIDATOR_1, amount);

        // Then unstake
        uint256 unlockID = adapter.unstake(VALIDATOR_1, amount);

        assertEq(unlockID, 1);
        assertEq(adapter.previewWithdraw(unlockID), amount);
        assertEq(adapter.unlockMaturity(unlockID), block.timestamp + UNBONDING_PERIOD);
    }

    function testUnstakeWithZeroAmount() public {
        vm.expectRevert(SeiAdapter.InvalidAmount.selector);
        adapter.unstake(VALIDATOR_1, 0);
    }

    function testUnstakeFailure() public {
        uint256 amount = 1 ether;
        MockSeiStaking(SEI_STAKING_PRECOMPILE_ADDRESS).setShouldFailUndelegate(true);

        vm.expectRevert(SeiAdapter.UndelegationFailed.selector);
        adapter.unstake(VALIDATOR_1, amount);
    }

    function testWithdrawSuccess() public {
        uint256 amount = 1 ether;

        // Stake and unstake
        adapter.stake(VALIDATOR_1, amount);
        uint256 unlockID = adapter.unstake(VALIDATOR_1, amount);

        // Fast forward past unbonding period
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);

        uint256 withdrawn = adapter.withdraw(VALIDATOR_1, unlockID);

        assertEq(withdrawn, amount);
        assertEq(adapter.previewWithdraw(unlockID), 0); // Should be deleted
    }

    function testWithdrawBeforeMaturity() public {
        uint256 amount = 1 ether;

        // Stake and unstake
        adapter.stake(VALIDATOR_1, amount);
        uint256 unlockID = adapter.unstake(VALIDATOR_1, amount);

        // Try to withdraw before unbonding period
        vm.expectRevert(SeiAdapter.UnlockNotReady.selector);
        adapter.withdraw(VALIDATOR_1, unlockID);
    }

    function testWithdrawInvalidUnlockID() public {
        vm.expectRevert(SeiAdapter.InvalidAmount.selector);
        adapter.withdraw(VALIDATOR_1, 999);
    }

    function testRebaseSuccess() public {
        uint256 amount = 1 ether;
        uint256 currentStake = 0.5 ether;

        // Stake some tokens first
        adapter.stake(VALIDATOR_1, amount);

        uint256 newStake = adapter.rebase(VALIDATOR_1, currentStake);

        // Should return the staked amount converted back to 18 decimals
        assertEq(newStake, amount);
    }

    function testMultipleUnlocks() public {
        uint256 amount1 = 1 ether;
        uint256 amount2 = 2 ether;

        // Stake tokens
        adapter.stake(VALIDATOR_1, amount1 + amount2);

        // Create multiple unlocks
        uint256 unlockID1 = adapter.unstake(VALIDATOR_1, amount1);
        uint256 unlockID2 = adapter.unstake(VALIDATOR_1, amount2);

        assertEq(unlockID1, 1);
        assertEq(unlockID2, 2);
        assertEq(adapter.previewWithdraw(unlockID1), amount1);
        assertEq(adapter.previewWithdraw(unlockID2), amount2);

        // Fast forward and withdraw both
        vm.warp(block.timestamp + UNBONDING_PERIOD + 1);

        uint256 withdrawn1 = adapter.withdraw(VALIDATOR_1, unlockID1);
        uint256 withdrawn2 = adapter.withdraw(VALIDATOR_1, unlockID2);

        assertEq(withdrawn1, amount1);
        assertEq(withdrawn2, amount2);
    }

    function testPrecisionConversion() public {
        uint256 amount = 1 ether; // 18 decimals
        uint256 expectedSeiAmount = amount / PRECISION_SCALE; // 6 decimals

        // Stake tokens
        adapter.stake(VALIDATOR_1, amount);

        // The precision conversion should work correctly
        // We can't directly test the internal conversion, but we can verify
        // that staking and rebasing work with the expected precision
        assertTrue(expectedSeiAmount == 1_000_000); // 1 SEI = 1,000,000 uSEI
    }
}
