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

import { Test, console2 } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

import { MultiValidatorFactory } from "core/multi-validator/Factory.sol";
import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { UnstakeNFT } from "core/multi-validator/MultiValidatorLST.sol";

import { Tenderizer } from "core/tenderizer/Tenderizer.sol";

import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";

import { GRT } from "core/adapters/GraphAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

// Existing GRT Tenderizer addresses on Arbitrum
address constant TENDERIZER_1 = 0x3458BB72b03B5ca1Cf5fd8C7a071B828Ea27d75b;
address constant TENDERIZER_2 = 0x28196d85e9c373f51CB13F95860aC02F6D184E58;
address constant TENDERIZER_3 = 0x9e0c3A2d1DdC81017083409bDD3f9bA07a3191D4;
address constant TENDERIZER_4 = 0xeab62Fb116f2e1f766A8a64094389553a00C2F68;
address constant TENDERIZER_5 = 0x6469F96a6E9aB573cC4805be369d1da4BF6d1769;
address constant TENDERIZER_6 = 0xCC1e5ed617eE900Fd02AddD679ef2bBDC5F910Bc;
address constant TENDERIZER_7 = 0xfF14e5D8ce40666eE9394cf036f3024D92e181d3;
address constant TENDERIZER_8 = 0x08a60C1173b00f3e00b95B8d146c1Acd0b06B6D6;
address constant TENDERIZER_9 = 0x71B27d308A8ae816D6e583e5f4992110d12f2b92;
address constant TENDERIZER_10 = 0xC6a97c176b809A30F3e3e41B8e822D86d3349916;
address constant TENDERIZER_11 = 0xF157AE69D25931E386E51B653be31E19598c6545;
address constant TENDERIZER_12 = 0x8CB1fDcD22c4cA8f477E2a2B841D56C5cF09b081;
address constant TENDERIZER_13 = 0x27Fe8C05aD08c48A854118ecA2703cb3B7b4651d;

address constant alice = address(0x5678);
address constant bob = address(0x9ABC);
address constant registry = 0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE;

// Livepeer specific
address constant minter = 0xc20DE37170B45774e6CD3d2304017fc962f27252; // GRT Minter address

// ILivepeerRounds constant ROUNDS = ILivepeerRounds(address(LIVEPEER_ROUNDS));
// uint256 constant ROUND_LENGTH = 6377; // round length in blocks
address constant GOVERNOR = 0x8C6de8F8D562f3382417340A6994601eE08D3809;

// interface ILivepeerRounds is ILivepeerRoundsManager {
//     function initializeRound() external;
// }

contract MultiValidatorLSTTest is Test, ERC721Receiver {
    // function _processRounds(uint256 rounds) internal {
    //     for (uint256 i = 0; i < rounds; i++) {
    //         uint256 currentRoundStartBlock = ROUNDS.currentRoundStartBlock();
    //         vm.roll(currentRoundStartBlock + ROUND_LENGTH);
    //         ROUNDS.initializeRound();
    //     }
    // }
    address immutable MINTER_ROLE = makeAddr("MINTER_ROLE");

    address immutable deployer = 0xc1cFab553835D74717c4499793EEa6Ef198A3031;

    MultiValidatorFactory factory;

    MultiValidatorLST lst;

    function mintTokens(address to, uint256 amount) public {
        vm.prank(MINTER_ROLE);
        MockERC20(address(GRT)).mint(to, amount);
    }

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"), 326_906_474);
        // Use labeled addresses for better test output
        vm.label(TENDERIZER_1, "Tenderizer1");
        vm.label(TENDERIZER_2, "Tenderizer2");
        vm.label(TENDERIZER_3, "Tenderizer3");
        vm.label(deployer, "Deployer");
        vm.label(alice, "Alice");
        vm.label(bob, "Bob");

        address factoryImpl = address(new MultiValidatorFactory());
        factory =
            MultiValidatorFactory(address(new ERC1967Proxy{ salt: bytes32("MultiValidatorLSTFactory") }(address(factoryImpl), "")));
        factory.initialize();

        vm.startPrank(deployer);
        lst = MultiValidatorLST(factory.deploy(address(GRT)));
        lst.setFee(0.05e6); // 5% fee

        lst.addValidator(payable(TENDERIZER_1), 3_000_000 ether); // 3M Stake
        lst.addValidator(payable(TENDERIZER_2), 2_000_000 ether); // 2M Stake
        lst.addValidator(payable(TENDERIZER_3), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_4), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_5), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_6), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_7), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_8), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_9), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_10), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_11), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_12), 1_000_000 ether); // 1M Stake
        lst.addValidator(payable(TENDERIZER_13), 1_000_000 ether); // 1M Stake

        vm.stopPrank();

        // Add MINTER_ROLE
        vm.prank(GOVERNOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(GRT).call(abi.encodeWithSignature("addMinter(address)", (address(MINTER_ROLE))));
    }

    function test_genesis_state() public {
        assertEq(lst.name(), "Steaked GRT", "Name should be 'Steaked GRT'");
        assertEq(lst.symbol(), "stGRT", "Symbol should be 'sGRT'");
        assertEq(lst.fee(), 0.05e6, "Fee should be set to 5%");
        assertEq(lst.totalAssets(), 0, "Initial total assets should be 0");
        assertEq(lst.totalSupply(), 0, "Initial total supply should be 0");

        // Check validators are properly set up
        (address tToken1, uint256 target1,) = lst.stakingPools(0);
        (address tToken2, uint256 target2,) = lst.stakingPools(1);
        (address tToken3, uint256 target3,) = lst.stakingPools(2);

        assertEq(tToken1, TENDERIZER_1, "First validator should be TENDERIZER_1");
        assertEq(tToken2, TENDERIZER_2, "Second validator should be TENDERIZER_2");
        assertEq(tToken3, TENDERIZER_3, "Third validator should be TENDERIZER_3");

        assertEq(target1, 3_000_000 ether, "First validator target weight should be 3M");
        assertEq(target2, 2_000_000 ether, "Second validator target weight should be 2M");
        assertEq(target3, 1_000_000 ether, "Third validator target weight should be 1M");

        assertEq(lst.validatorCount(), 13, "Validator count should be 13");
    }

    function test_deposit() public {
        uint256 depositAmount = 10 ether;

        mintTokens(alice, depositAmount);

        (address tToken1,, uint256 balance1) = lst.stakingPools(0);
        (address tToken2,, uint256 balance2) = lst.stakingPools(1);
        (address tToken3,, uint256 balance3) = lst.stakingPools(2);

        vm.startPrank(alice);

        // Approve GRT transfer to LST
        GRT.approve(address(lst), depositAmount);

        // Record initial balances
        uint256 initialGRTBalance = GRT.balanceOf(alice);

        // Deposit GRT to LST
        uint256 shares = lst.deposit(alice, depositAmount);

        vm.stopPrank();

        // Assert Alice received shares
        assertGt(shares, 0, "Alice should receive shares");
        assertEq(lst.balanceOf(alice), shares, "Alice should have shares in LST");

        // Assert Alice's GRT balance decreased
        assertEq(GRT.balanceOf(alice), initialGRTBalance - depositAmount, "Alice's GRT balance should decrease");
        assertEq(lst.balanceOf(alice), shares, "Alice's LST balance should increase");
        // Assert total assets increased

        // Assert stake was distributed across validators according to targets
        (,, balance1) = lst.stakingPools(0);
        (,, balance2) = lst.stakingPools(1);
        (,, balance3) = lst.stakingPools(2);
        uint256 tTokenBalance1 = Tenderizer(payable(tToken1)).balanceOf(address(lst));
        uint256 tTokenBalance2 = Tenderizer(payable(tToken2)).balanceOf(address(lst));
        uint256 tTokenBalance3 = Tenderizer(payable(tToken3)).balanceOf(address(lst));

        assertEq(balance1, tTokenBalance1, "Validator 1 balance should increase");
        assertEq(balance2, tTokenBalance2, "Validator 2 balance should increase");
        assertEq(balance3, tTokenBalance3, "Validator 3 balance should increase");
        // The sum of all tToken balances should equal total assets
        assertEq(
            tTokenBalance1 + tTokenBalance2 + tTokenBalance3,
            lst.totalAssets(),
            "Sum of validator balances should equal total tTokens"
        );

        // Since all validators start with 0 balance and the divergence is negative for all,
        // distribution should prioritize the validators with highest target weight to balance them
        // We'd expect more to go to validator 1, then 2, then 3
        assertGt(balance1, balance2, "Validator 1 should receive more than Validator 2");
        assertGt(balance2, balance3, "Validator 2 should receive more than Validator 3");
    }

    // function test_unwrap() public {
    //     uint256 depositAmount = 1_000_000 ether;

    //     // Mint tokens for Alice
    //     mintTokens(alice, depositAmount);

    //     // Get initial validator data
    //     (address tToken1,,) = lst.stakingPools(0);
    //     (address tToken2,,) = lst.stakingPools(1);
    //     (address tToken3,,) = lst.stakingPools(2);

    //     // Setup: Alice deposits first
    //     vm.startPrank(alice);
    //     GRT.approve(address(lst), depositAmount);
    //     uint256 shares = lst.deposit(alice, depositAmount);

    //     // Record balances after deposit
    //     (,, uint256 balance1AfterDeposit) = lst.stakingPools(0);
    //     (,, uint256 balance2AfterDeposit) = lst.stakingPools(1);
    //     (,, uint256 balance3AfterDeposit) = lst.stakingPools(2);

    //     // Unwrap half of Alice's shares
    //     uint256 sharesToUnwrap = shares / 2;
    //     uint256 expectedAmount = lst.totalAssets() / 2; // Since 1:1 ratio

    //     // Perform unwrap with minimum amount check (allow 1% slippage)
    //     (, uint256[] memory amounts) = lst.unwrap(sharesToUnwrap, expectedAmount);
    //     vm.stopPrank();

    //     // Assert Alice's shares were burned
    //     assertEq(lst.balanceOf(alice), shares - sharesToUnwrap, "Alice's shares should decrease");
    //     assertEq(
    //         FixedPointMathLib.mulWad(lst.balanceOf(alice), lst.exchangeRate()),
    //         expectedAmount,
    //         "Alice's GRT balance should increase"
    //     );
    //     // Assert total assets decreased
    //     assertEq(lst.totalAssets(), expectedAmount, "Total assets should decrease by half");

    //     console2.log("total assets", lst.totalAssets());
    //     console2.log("alice expected underlying", FixedPointMathLib.mulWad(lst.balanceOf(alice), lst.exchangeRate()));
    //     // // calculate draw from each tToken
    //     // uint256 draw1;
    //     // uint256 draw2;
    //     // uint256 draw3;
    //     // {
    //     //     uint256 avgStake = FixedPointMathLib.divWad(10 ether, 3);
    //     //     uint256 maxDraw = FixedPointMathLib.divWad(avgStake, 2);

    //     //     draw1 = maxDraw > balance1AfterDeposit ? balance1AfterDeposit : balance1AfterDeposit - maxDraw;
    //     //     draw2 = maxDraw > balance2AfterDeposit ? balance2AfterDeposit : balance2AfterDeposit - maxDraw;
    //     //     draw3 = maxDraw > balance3AfterDeposit ? balance3AfterDeposit : balance3AfterDeposit - maxDraw;
    //     // }
    //     // /*
    //     // uint256 max = maxDrawdown > pool.balance ? pool.balance : pool.balance - maxDrawdown; // Edge case with rounding
    //     //     uint256 draw = max < remaining ? max : remaining;
    //     // */
    //     // // Check validator balances after unwrap
    //     // {
    //     //     (,, uint256 balance1AfterUnwrap) = lst.stakingPools(0);
    //     //     (,, uint256 balance2AfterUnwrap) = lst.stakingPools(1);
    //     //     (,, uint256 balance3AfterUnwrap) = lst.stakingPools(2);

    //     //     // Verify that validator balances decreased
    //     //     assertEq(balance1AfterUnwrap, balance1AfterDeposit - draw1, "Validator 1 balance should decrease");
    //     //     assertEq(balance2AfterUnwrap, balance2AfterDeposit - draw1, "Validator 2 balance should decrease");
    //     //     assertEq(balance3AfterUnwrap, balance3AfterDeposit - draw1, "Validator 3 balance should decrease");
    //     // }

    //     // assertEq(amounts[0], draw1, "Returned tToken1 amount should match drawn amount");
    //     // assertEq(amounts[1], draw2, "Returned tToken2 amount should match drawn amount");
    //     // assertEq(amounts[2], draw3, "Returned tToken3 amount should match drawn amount");
    //     // assertEq(Tenderizer(payable(tToken1)).balanceOf(alice), draw1, "Alice should receive correct tToken1 amount");
    //     // assertEq(Tenderizer(payable(tToken2)).balanceOf(alice), draw2, "Alice should receive correct tToken2 amount");
    //     // assertEq(Tenderizer(payable(tToken3)).balanceOf(alice), draw3, "Alice should receive correct tToken3 amount");

    //     //     // The tTokens Alice receives should match what the validators lost
    //     //     assertEq(aliceTToken1Received, balance1AfterDeposit - balance1AfterUnwrap, "Alice should receive correct tToken1
    //     // amount");
    //     //     assertEq(aliceTToken2Received, balance2AfterDeposit - balance2AfterUnwrap, "Alice should receive correct tToken2
    //     // amount");
    //     //     assertEq(aliceTToken3Received, balance3AfterDeposit - balance3AfterUnwrap, "Alice should receive correct tToken3
    //     // amount");

    //     //     // The sum of received tToken amounts should equal the unwrapped value (half the deposit)
    //     //     uint256 totalReceived = aliceTToken1Received + aliceTToken2Received + aliceTToken3Received;
    //     //     assertEq(totalReceived, expectedAmount, "Total received should match expected unwrap amount");

    //     //     // Verify the returned tTokens and amounts match what Alice received
    //     //     bool foundToken1 = false;
    //     //     bool foundToken2 = false;
    //     //     bool foundToken3 = false;

    //     //     for (uint256 i = 0; i < tTokens.length; i++) {
    //     //         if (tTokens[i] == tToken1) {
    //     //             assertEq(amounts[i], aliceTToken1Received, "Returned tToken1 amount should match received");
    //     //             foundToken1 = true;
    //     //         } else if (tTokens[i] == tToken2) {
    //     //             assertEq(amounts[i], aliceTToken2Received, "Returned tToken2 amount should match received");
    //     //             foundToken2 = true;
    //     //         } else if (tTokens[i] == tToken3) {
    //     //             assertEq(amounts[i], aliceTToken3Received, "Returned tToken3 amount should match received");
    //     //             foundToken3 = true;
    //     //         }
    //     //     }

    //     //     // Ensure all tokens were accounted for in the return values
    //     //     assertTrue(foundToken1 || aliceTToken1Received == 0, "tToken1 should be in return array if amount > 0");
    //     //     assertTrue(foundToken2 || aliceTToken2Received == 0, "tToken2 should be in return array if amount > 0");
    //     //     assertTrue(foundToken3 || aliceTToken3Received == 0, "tToken3 should be in return array if amount > 0");
    //     // }
    // }

    // function test_unstake_withdraw() public {
    //     uint256 depositAmount = 1_000_000 ether;

    //     // Mint tokens for Alice
    //     mintTokens(alice, depositAmount);

    //     // Setup: Alice deposits first
    //     vm.startPrank(alice);
    //     GRT.approve(address(lst), depositAmount);
    //     uint256 shares = lst.deposit(alice, depositAmount);

    //     //_processRounds(1);

    //     uint256 sharesToUnstake = shares / 2;
    //     uint256 expectedAmount = FixedPointMathLib.mulWad(sharesToUnstake, lst.exchangeRate());
    //     uint256 id = lst.unstake(sharesToUnstake, expectedAmount);

    //     assertEq(id, 1, "Unstake ID should be 1");

    //     MultiValidatorLST.UnstakeRequest memory req = lst.getUnstakeRequest(id);

    //     for (uint256 i = 0; i < req.tTokens.length; i++) {
    //         console2.log("tToken %s", req.tTokens[i]);
    //     }

    //     assertEq(req.amount, expectedAmount, "Unstake request amount should match expected amount");

    //     // _processRounds(7);

    //     uint256 balBefore = GRT.balanceOf(alice);
    //     uint256 amount = lst.withdraw(id);
    //     uint256 balAfter = GRT.balanceOf(alice);

    //     assertEq(amount, balAfter - balBefore, "Withdraw amount should match expected amount");
    // }
}
