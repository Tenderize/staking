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
import { TestHelpers } from "test/helpers/Helpers.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { IERC20, IERC20Metadata } from "core/interfaces/IERC20.sol";
import { Adapter, TenderizerHarness } from "test/tenderizer/Tenderizer.harness.sol";
import { AdapterDelegateCall } from "core/adapters/Adapter.sol";
import { TenderizerEvents } from "core/tenderizer/TenderizerBase.sol";
import { StaticCallFailed } from "core/tenderizer/Tenderizer.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Registry } from "core/registry/Registry.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

contract TenderizerSetup is Test, TestHelpers {
    using ClonesWithImmutableArgs for address;

    uint256 internal constant MAX_UINT = type(uint256).max;
    uint256 internal MAX_UINT_SQRT = sqrt(MAX_UINT - 1);

    uint256 internal constant MAX_FEE = 0.005 ether;

    address internal asset = vm.addr(1);
    address internal staking = vm.addr(2);

    TenderizerHarness internal tenderizer;
    address internal router = vm.addr(3);
    address internal adapter = vm.addr(4);
    address internal unlocks = vm.addr(5);

    address internal account1 = vm.addr(6);
    address internal account2 = vm.addr(7);

    address internal validator = vm.addr(8);
    address internal treasury = vm.addr(9);

    bytes internal constant ERROR_MESSAGE = "ADAPTER_CALL_FAILED";

    string internal symbol = "FOO";

    function setUp() public {
        // Setup global mock responses
        vm.mockCall(router, abi.encodeCall(Registry.adapter, (asset)), abi.encode(adapter));
        vm.mockCall(router, abi.encodeCall(Registry.fee, (asset)), abi.encode(0.05 ether));
        vm.mockCall(router, abi.encodeCall(Registry.treasury, ()), abi.encode(treasury));
        vm.mockCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode(symbol));

        tenderizer = TenderizerHarness(address(new TenderizerHarness()).clone(abi.encodePacked(asset, validator, router, unlocks)));
    }
}

// solhint-disable func-name-mixedcase
contract TenderizerTest is TenderizerSetup, TenderizerEvents {
    function test_Name() public {
        vm.expectCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()));
        assertEq(tenderizer.name(), string(abi.encodePacked("tender", symbol, " ", validator)), "invalid name");
    }

    function test_Symbol() public {
        vm.expectCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()));
        assertEq(tenderizer.symbol(), string(abi.encodePacked("t", symbol, "_", validator)), "invalid symbol");
    }

    function test_InitialVaules() public {
        assertEq(address(tenderizer.asset()), asset, "invalid asset");
        assertEq(address(tenderizer.validator()), validator, "invalid validator");
        assertEq(address(tenderizer.exposed_registry()), router, "invalid router");
        assertEq(address(tenderizer.exposed_unlocks()), unlocks, "invalid unlocks");
        assertEq(address(tenderizer.exposed_adapter()), adapter, "invalid adapter");
    }

    function test_PreviewDeposit() public {
        uint256 amountIn = 100 ether;
        uint256 amountOut = 99.5 ether;
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (amountIn)), abi.encode(amountOut));
        vm.expectCall(adapter, abi.encodeCall(Adapter.previewDeposit, (amountIn)));
        assertEq(tenderizer.previewDeposit(amountIn), amountOut);
    }

    function test_PreviewDeposit_RevertIfAdapterReverts() public {
        vm.mockCallRevert(adapter, abi.encodeCall(Adapter.previewDeposit, (1 ether)), ERROR_MESSAGE);
        vm.expectRevert(
            abi.encodeWithSelector(
                StaticCallFailed.selector, address(tenderizer), abi.encodeCall(tenderizer._previewDeposit, (1 ether)), ""
            )
        );
        tenderizer.previewDeposit(1 ether);
    }

    function test_UnlockMaturity() public {
        uint256 unlockID = 1;
        uint256 unlockTime = block.timestamp;
        vm.mockCall(adapter, abi.encodeCall(Adapter.unlockMaturity, (unlockID)), abi.encode(unlockTime));
        vm.expectCall(adapter, abi.encodeCall(Adapter.unlockMaturity, (unlockID)));
        assertEq(tenderizer.unlockMaturity(unlockID), unlockTime);
    }

    function test_PreviewWithdraw() public {
        uint256 amount = 1 ether;
        uint256 unlockID = 1;
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewWithdraw, (unlockID)), abi.encode(amount));
        vm.expectCall(adapter, abi.encodeCall(Adapter.previewWithdraw, (unlockID)));
        assertEq(tenderizer.previewWithdraw(unlockID), amount);
    }

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 1, MAX_UINT_SQRT);
        _deposit(account1, amount, 0);
        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, amount)), abi.encode(amount));

        vm.prank(account1);
        vm.expectCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, amount)));
        vm.expectCall(address(tenderizer), abi.encodeCall(TToken.transfer, (account2, amount)));
        tenderizer.transfer(account2, amount);
    }

    function testFuzz_TransferFrom(uint256 amount) public {
        amount = bound(amount, 1, MAX_UINT_SQRT);
        _deposit(account1, amount, 0);

        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, amount)), abi.encode(amount));
        vm.expectCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, amount)));
        vm.expectCall(address(tenderizer), abi.encodeCall(TToken.transferFrom, (account1, account2, amount)));
        vm.prank(account1);
        tenderizer.approve(account2, amount);
        vm.prank(account2);
        tenderizer.transferFrom(account1, account2, amount);
    }

    function testFuzz_Deposit(uint256 amountIn, uint256 amountOut) public {
        amountIn = bound(amountIn, 1, MAX_UINT_SQRT);
        amountOut = bound(amountOut, 1, MAX_UINT_SQRT);

        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, 0)), abi.encode(0));
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (amountIn)), abi.encode(amountOut));
        vm.mockCall(asset, abi.encodeCall(IERC20.transferFrom, (account1, address(tenderizer), amountIn)), abi.encode(true));

        vm.expectCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, 0)));
        vm.expectCall(asset, abi.encodeCall(IERC20.transferFrom, (account1, address(tenderizer), amountIn)));
        vm.expectCall(adapter, abi.encodeCall(Adapter.previewDeposit, (amountIn)));
        vm.expectCall(adapter, abi.encodeCall(Adapter.stake, (validator, amountIn)));
        vm.expectEmit(true, true, true, true);
        emit Deposit(account1, account2, amountIn, amountOut);

        vm.prank(account1);
        uint256 actualAssets = tenderizer.deposit(account2, amountIn);

        assertEq(actualAssets, amountOut, "invalid return value");
        assertEq(tenderizer.balanceOf(address(account2)), amountOut, "mint failed");
    }

    function test_Deposit_RevertIfStakeReverts() public {
        uint256 depositAmount = 100 ether;
        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, 0)), abi.encode(0));
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (depositAmount)), abi.encode(depositAmount));
        vm.mockCallRevert(
            adapter,
            abi.encodeCall(Adapter.stake, (validator, depositAmount)),
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );
        vm.expectRevert(abi.encodeWithSelector(AdapterDelegateCall.AdapterDelegateCallFailed.selector, ERROR_MESSAGE));
        tenderizer.deposit(account1, depositAmount);
    }

    function test_Deposit_RevertIfZeroAmount() public {
        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, 0)), abi.encode(0));
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (0)), abi.encode(0));
        vm.expectRevert(TToken.ZeroAmount.selector);
        tenderizer.deposit(account1, 0);
    }

    function test_Deposit_RevertIfAssetTransferFails() public {
        uint256 depositAmount = 100 ether;
        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, 0)), abi.encode(0));
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (depositAmount)), abi.encode(depositAmount));
        vm.mockCall(asset, abi.encodeCall(IERC20.transferFrom, (account1, address(tenderizer), depositAmount)), abi.encode(false));
        vm.prank(account1);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        tenderizer.deposit(account1, depositAmount);
    }

    function testFuzz_Unlock(uint256 amount) public {
        uint256 depositAmount = 100 ether;
        uint256 unlockID = 1;
        amount = bound(amount, 1, depositAmount);

        _unlockPreReq(account1, depositAmount, amount, unlockID);

        vm.expectCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, depositAmount)));
        vm.expectCall(adapter, abi.encodeCall(Adapter.unstake, (validator, amount)));
        vm.expectCall(unlocks, abi.encodeCall(Unlocks.createUnlock, (account1, unlockID)));
        vm.expectEmit(true, true, true, true);
        emit Unlock(account1, amount, unlockID);
        vm.prank(account1);
        uint256 returnedUnlockID = tenderizer.unlock(amount);

        assertEq(returnedUnlockID, unlockID, "invalid return value");
        assertEq(tenderizer.balanceOf(account1), depositAmount - amount, "burn failed");
    }

    function test_Unlock_RevertIfAdapterCallReverts() public {
        uint256 depositAmount = 100 ether;
        uint256 unlockAmount = 10 ether;
        _unlockPreReq(account1, depositAmount, unlockAmount, 1);

        vm.mockCallRevert(
            adapter,
            abi.encodeCall(Adapter.unstake, (validator, unlockAmount)),
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );

        vm.prank(account1);
        vm.expectRevert(abi.encodeWithSelector(AdapterDelegateCall.AdapterDelegateCallFailed.selector, ERROR_MESSAGE));
        tenderizer.unlock(unlockAmount);
    }

    function test_unlock_RevertIfCreateUnlockFails() public {
        uint256 depositAmount = 100 ether;
        uint256 unlockAmount = 10 ether;
        uint256 unlockID = 1;
        _unlockPreReq(account1, depositAmount, unlockAmount, unlockID);

        vm.mockCall(adapter, abi.encodeCall(Adapter.unstake, (validator, unlockAmount)), abi.encode(unlockID));
        vm.mockCallRevert(
            unlocks,
            abi.encodeCall(Unlocks.createUnlock, (account1, unlockID)),
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );

        vm.prank(account1);
        vm.expectRevert(ERROR_MESSAGE);
        tenderizer.unlock(unlockAmount);
    }

    function test_Unlock_RevertIfZeroAmount() public {
        _unlockPreReq(account1, 1 ether, 0, 0);
        vm.expectRevert(abi.encodeWithSelector(TToken.ZeroAmount.selector));
        tenderizer.unlock(0);
    }

    function test_Unlock_RevertIfNotEnoughTenderTokens() public {
        uint256 depositAmount = 100 ether;
        uint256 unlockAmount = depositAmount + 1;

        _unlockPreReq(account1, depositAmount, unlockAmount, 0);

        vm.prank(account1);
        vm.expectRevert(stdError.arithmeticError);
        tenderizer.unlock(unlockAmount);
    }

    function testFuzz_Withdraw(uint256 amount) public {
        uint256 depositAmount = 100 ether;
        uint256 unlockID = 1;
        amount = bound(amount, 1, depositAmount);

        vm.mockCall(unlocks, abi.encodeCall(Unlocks.useUnlock, (account1, unlockID)), "");
        vm.mockCall(adapter, abi.encodeCall(Adapter.withdraw, (validator, unlockID)), abi.encode(amount));

        vm.expectCall(unlocks, abi.encodeCall(Unlocks.useUnlock, (account1, unlockID)));
        vm.expectCall(asset, abi.encodeCall(IERC20.transfer, (account2, amount)));
        vm.expectEmit(true, true, true, true);
        emit Withdraw(account2, amount, unlockID);
        vm.prank(account1);
        uint256 returnedAssets = tenderizer.withdraw(account2, unlockID);

        assertEq(returnedAssets, amount, "invalid return value");
    }

    function test_Withdraw_RevertIfAdapterCallReverts() public {
        uint256 unlockID = 1;
        vm.mockCall(unlocks, abi.encodeCall(Unlocks.useUnlock, (account1, unlockID)), "");
        vm.mockCallRevert(
            adapter,
            abi.encodeCall(Adapter.withdraw, (validator, unlockID)),
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );

        vm.expectRevert(abi.encodeWithSelector(AdapterDelegateCall.AdapterDelegateCallFailed.selector, ERROR_MESSAGE));
        tenderizer.withdraw(account1, unlockID);
    }

    function test_Withdraw_RevertIfUseUnlockFails() public {
        uint256 unlockID = 1;
        // Calls to mocked addresses may revert if there is no code on the address.
        // To circumvent this, use the etch cheatcode if the mocked address has no code.
        // From https://book.getfoundry.sh/cheatcodes/mock-call
        vm.etch(unlocks, "0");
        vm.mockCallRevert(
            unlocks,
            abi.encodeCall(Unlocks.useUnlock, (account1, unlockID)),
            abi.encodeWithSignature("Error(string)", ERROR_MESSAGE)
        );

        vm.prank(account1);
        vm.expectRevert(ERROR_MESSAGE);
        tenderizer.withdraw(account2, unlockID);
    }

    function testFuzz_Rebase_Positive(uint256 depositSeed, uint256 rewards, uint256 feeRate) public {
        uint256 deposit1 = rand(depositSeed, 0, 1, MAX_UINT_SQRT / 4);
        uint256 deposit2 = rand(depositSeed, 1, 1, MAX_UINT_SQRT / 4);
        uint256 totalDeposit = deposit1 + deposit2;
        // new stake can at most double
        // newStake >>> totalShares causes larger errors in calculations
        rewards = bound(rewards, 0, 2 * totalDeposit);
        feeRate = bound(feeRate, 0, 2 ether);
        uint256 newStake = totalDeposit + rewards;

        _deposit(account1, deposit1, 0);
        _deposit(account2, deposit2, deposit1);

        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, totalDeposit)), abi.encode(newStake));

        vm.mockCall(router, abi.encodeCall(Registry.fee, (asset)), abi.encode(feeRate));

        uint256 cappedFeeRate = feeRate > MAX_FEE ? MAX_FEE : feeRate;
        uint256 expFees = ((newStake - totalDeposit) * cappedFeeRate) / 1 ether;

        vm.expectEmit(true, true, true, true);
        emit Rebase(totalDeposit, newStake);
        tenderizer.rebase();

        assertLt(absDiff(tenderizer.totalSupply(), newStake), 5, "invalid totalSupply");
        assertLt(
            absDiff(tenderizer.balanceOf(account1), (newStake - expFees) * deposit1 / totalDeposit), 5, "invalid account1 balance"
        );
        assertLt(
            absDiff(tenderizer.balanceOf(account2), (newStake - expFees) * deposit2 / totalDeposit), 5, "invalid account2 balance"
        );
        assertLt(absDiff(tenderizer.balanceOf(address(treasury)), expFees), 5, "invalid fees minted");
    }

    function testFuzz_Rebase_Negative(uint256 depositSeed, uint256 slash) public {
        uint256 deposit1 = rand(depositSeed, 0, 1, MAX_UINT_SQRT / 4);
        uint256 deposit2 = rand(depositSeed, 1, 1, MAX_UINT_SQRT / 4);
        uint256 totalDeposit = deposit1 + deposit2;
        slash = bound(slash, 0, totalDeposit);
        uint256 newStake = totalDeposit - slash;

        _deposit(account1, deposit1, 0);
        _deposit(account2, deposit2, deposit1);

        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, totalDeposit)), abi.encode(newStake));
        vm.mockCall(router, abi.encodeCall(Registry.fee, (asset)), abi.encode(0.01 ether));

        vm.expectEmit(true, true, true, true);
        emit Rebase(totalDeposit, newStake);
        tenderizer.rebase();

        assertEq(tenderizer.totalSupply(), newStake, "invalid totalSupply");
        assertEq(tenderizer.balanceOf(account1), (newStake * deposit1) / totalDeposit, "invalid account1 balance");
        assertEq(tenderizer.balanceOf(account2), (newStake * deposit2) / totalDeposit, "invalid account2 balance");
    }

    function test_Rebase_Neutral() public {
        uint256 deposit1 = 1 ether;
        uint256 deposit2 = 2 ether;
        uint256 totalDeposit = deposit1 + deposit2;

        _deposit(account1, deposit1, 0);
        _deposit(account2, deposit2, deposit1);

        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, totalDeposit)), abi.encode(totalDeposit));
        vm.mockCall(router, abi.encodeCall(Registry.fee, (asset)), abi.encode(0.01 ether));

        vm.expectEmit(true, true, true, true);
        emit Rebase(totalDeposit, totalDeposit);
        tenderizer.rebase();

        assertEq(tenderizer.totalSupply(), totalDeposit, "invalid totalSupply");
        assertEq(tenderizer.balanceOf(account1), deposit1, "invalid account1 balance");
        assertEq(tenderizer.balanceOf(account2), deposit2, "invalid account2 balance");
    }

    function _deposit(address account, uint256 amount, uint256 totalPreviousDeposits) internal {
        vm.mockCall(adapter, abi.encodeCall(Adapter.previewDeposit, (amount)), abi.encode(amount));
        vm.mockCall(
            adapter, abi.encodeCall(Adapter.claimRewards, (validator, totalPreviousDeposits)), abi.encode(totalPreviousDeposits)
        );
        vm.prank(account);
        tenderizer.deposit(account, amount);
    }

    function _unlockPreReq(address account, uint256 depositAmount, uint256 unlockAmount, uint256 unlockID) internal {
        _deposit(account, depositAmount, 0);

        vm.mockCall(adapter, abi.encodeCall(Adapter.unstake, (validator, unlockAmount)), abi.encode(unlockID));
        vm.mockCall(unlocks, abi.encodeCall(Unlocks.createUnlock, (account1, unlockID)), abi.encode(unlockID));
        vm.mockCall(adapter, abi.encodeCall(Adapter.claimRewards, (validator, depositAmount)), abi.encode(depositAmount));
    }
}
