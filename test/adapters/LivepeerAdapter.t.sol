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
import { ISwapRouter } from "core/adapters/interfaces/ISwapRouter.sol";
import { IWETH9 } from "core/adapters/interfaces/IWETH9.sol";
import { LivepeerAdapter } from "core/adapters/LivepeerAdapter.sol";
import { IERC20 } from "core/interfaces/IERC20.sol";
import { TestHelpers } from "test/helpers/Helpers.sol";

// solhint-disable func-name-mixedcase

contract LivepeerAdapterTest is Test, LivepeerAdapter, TestHelpers {
    address private validator = vm.addr(1);
    address private livepeerBonding = 0x35Bcf3c30594191d53231E4FF333E8A770453e40;
    address private livepeerRounds = 0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f;
    address private lpt = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
    address private weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address private uniswapRouter = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    uint24 private constant UNISWAP_POOL_FEE = 10_000;

    uint256 private constant WITHDRAW_ROUND = 10;
    uint256 private MAX_UINT_SQRT = sqrt(type(uint256).max - 1);
    uint256 private constant ROUND_LENGTH = 25;

    function testFuzz_PreviewDeposit(uint256 assets) public {
        assertEq(this.previewDeposit(assets), assets);
    }

    function test_PreviewWithdraw() public {
        uint256 unlockId = 0;
        uint256 amount = 1 ether;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegatorUnbondingLock.selector, address(this), unlockId),
            abi.encode(amount, 0)
        );

        vm.expectCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegatorUnbondingLock.selector, address(this), unlockId)
        );
        assertEq(this.previewWithdraw(unlockId), amount);
    }

    function test_GetTotalStaked() public {
        uint256 stake = 1 ether;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.pendingStake.selector, address(this), 0),
            abi.encode(stake)
        );

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.pendingStake.selector, address(this), 0));
        assertEq(this.getTotalStaked(address(this)), stake);
    }

    function testFuzz_UnlockMaturity(uint256 currentRound) public {
        vm.roll(rand(1, 1, 100, MAX_UINT_SQRT));
        uint256 currentRoundStartBlock = block.number - 20;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegatorUnbondingLock.selector),
            abi.encode(0, WITHDRAW_ROUND)
        );

        vm.mockCall(
            livepeerRounds,
            abi.encodeWithSelector(ILivepeerRoundsManager.currentRoundStartBlock.selector),
            abi.encode(currentRoundStartBlock)
        );

        uint256 unlockID = 0;
        uint256 maturity;
        uint256 blockRemainingInCurrentRound = ROUND_LENGTH - (block.number - currentRoundStartBlock);
        vm.mockCall(livepeerRounds, abi.encodeWithSelector(ILivepeerRoundsManager.currentRound.selector), abi.encode(currentRound));
        vm.mockCall(livepeerRounds, abi.encodeWithSelector(ILivepeerRoundsManager.roundLength.selector), abi.encode(ROUND_LENGTH));

        if (WITHDRAW_ROUND > currentRound) {
            maturity = ROUND_LENGTH * (WITHDRAW_ROUND - currentRound - 1) + blockRemainingInCurrentRound;
            assertEq(this.unlockMaturity(unlockID), maturity, "incorrect maturity");
        } else {
            assertEq(this.unlockMaturity(unlockID), maturity, "maturity should be 0");
        }
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
        uint256 unlockId = 1;
        vm.mockCall(
            livepeerBonding,
            abi.encodeWithSelector(ILivepeerBondingManager.getDelegator.selector, address(this)),
            abi.encode(0, 0, vm.addr(2), 0, 0, 0, unlockId)
        );
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.unbond.selector, amount), "");

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.getDelegator.selector, address(this)));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.unbond.selector, amount));
        assertEq(this.unstake(validator, amount), unlockId);
    }

    function test_Withdraw() public {
        uint256 unlockId = 0;
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawStake.selector, unlockId), "");

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawStake.selector, unlockId));
        this.withdraw(validator, unlockId);
    }

    function test_ClaimRewards() public {
        vm.mockCall(
            livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.pendingFees.selector, address(this), 0), abi.encode(10)
        );
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawFees.selector, address(this), 10), "");
        vm.mockCall(weth, abi.encodeWithSelector(IWETH9.deposit.selector), "");
        vm.mockCall(weth, abi.encodeWithSelector(IERC20.approve.selector, uniswapRouter, address(this).balance), "");

        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(weth),
            tokenOut: address(address(lpt)),
            fee: UNISWAP_POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: address(this).balance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        vm.mockCall(uniswapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params), abi.encode(1000));
        vm.expectCall(uniswapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params));

        params.amountOutMinimum = 1000;
        vm.mockCall(uniswapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params), abi.encode(1100));
        vm.expectCall(uniswapRouter, abi.encodeWithSelector(ISwapRouter.exactInputSingle.selector, params));

        vm.mockCall(lpt, abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)), abi.encode(10));
        vm.mockCall(lpt, abi.encodeWithSelector(IERC20.approve.selector, livepeerBonding, 10), abi.encode(true));
        vm.mockCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.bond.selector, 10, validator), "");
        vm.mockCall(
            livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.pendingStake.selector, address(this), 0), abi.encode(20)
        );

        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.pendingFees.selector, address(this), 0));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.withdrawFees.selector, address(this), 10));
        vm.expectCall(weth, abi.encodeWithSelector(IWETH9.deposit.selector));
        vm.expectCall(weth, abi.encodeWithSelector(IERC20.approve.selector, uniswapRouter, address(this).balance));
        vm.expectCall(lpt, abi.encodeWithSelector(IERC20.balanceOf.selector, address(this)));
        vm.expectCall(lpt, abi.encodeWithSelector(IERC20.approve.selector, livepeerBonding, 10));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.bond.selector, 10, validator));
        vm.expectCall(livepeerBonding, abi.encodeWithSelector(ILivepeerBondingManager.pendingStake.selector, address(this), 0));
        assertEq(this.claimRewards(validator, 0), 20);
    }
}
