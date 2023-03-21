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
import { ILivepeerBondingManager, ILivepeerRoundsManager } from "core/adapters/interfaces/ILivepeer.sol";
import { LivepeerAdapter } from "core/adapters/LivepeerAdapter.sol";
import { IERC20 } from "core/interfaces/IERC20.sol";

// solhint-disable func-name-mixedcase

contract LivepeerAdapterTest is Test, LivepeerAdapter {
    address private validator = vm.addr(1);
    address private livepeerBonding = 0x35Bcf3c30594191d53231E4FF333E8A770453e40;
    address private livepeerRounds = 0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f;
    address private lpt = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;

    uint256 private constant WITHDRAW_ROUND = 10;

    uint256 private constant ROUND_LENGTH = 25;
    uint256 private CURRENT_ROUND_START_BLOCK;

    function setUp() public {
        vm.roll(500);
        CURRENT_ROUND_START_BLOCK = block.number - 20;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegatorUnbondingLock.selector),
            abi.encode(0, WITHDRAW_ROUND)
        );

        vm.mockCall(
            livepeerRounds,
            abi.encodeWithSelector(ILivepeerRoundsManager.currentRoundStartBlock.selector),
            abi.encode(CURRENT_ROUND_START_BLOCK)
        );
    }

    function testFuzz_PreviewDeposit(uint256 assets) public {
        assertEq(this.previewDeposit(assets), assets);
    }

    function testFuzz_UnlockMaturity(uint256 currentRound) public {
        uint256 unlockID = 0;
        uint256 maturity;
        uint256 blockRemainingInCurrentRound = ROUND_LENGTH - (block.number - CURRENT_ROUND_START_BLOCK);
        vm.mockCall(livepeerRounds, abi.encodeWithSelector(ILivepeerRoundsManager.currentRound.selector), abi.encode(currentRound));
        vm.mockCall(livepeerRounds, abi.encodeWithSelector(ILivepeerRoundsManager.roundLength.selector), abi.encode(ROUND_LENGTH));

        this.unlockMaturity(unlockID);

        if (WITHDRAW_ROUND > currentRound) {
            maturity = ROUND_LENGTH * (WITHDRAW_ROUND - currentRound - 1) + blockRemainingInCurrentRound;
        }
        assertEq(this.unlockMaturity(unlockID), maturity);
    }

    function test_Stake() public {
        uint256 amount = 1 ether;
        vm.mockCall(lpt, abi.encodeWithSelector(IERC20.approve.selector, livepeerBonding, amount), abi.encode(true));
        vm.mockCall(
            livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.bond.selector, amount, validator), abi.encode(amount)
        );

        vm.expectCall(lpt, abi.encodeWithSelector(IERC20.approve.selector, livepeerBonding, amount));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.bond.selector, amount, validator));
        this.stake(validator, amount);
    }

    function test_Unstake() public {
        uint256 amount = 1 ether;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegator.selector, address(this)),
            abi.encode(0, 0, vm.addr(2), 0, 0, 0, 1)
        );
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.unbond.selector, amount), "");

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.getDelegator.selector, address(this)));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.unbond.selector, amount));
        this.unstake(validator, amount);
    }

    function test_Withdraw() public {
        uint256 unlockId = 0;
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawStake.selector, unlockId), "");

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawStake.selector, unlockId));
        this.withdraw(validator, unlockId);
    }
}
