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
import { ILivepeerBondingManager, ILivepeerRoundsManager } from "core/adapters/interfaces/ILivepeer.sol";
import { ISwapRouter } from "core/adapters/interfaces/ISwapRouter.sol";
import { IWETH9 } from "core/adapters/interfaces/IWETH9.sol";

contract LivepeerAdapter is Adapter {
    using SafeTransferLib for ERC20;

    ILivepeerBondingManager private constant LIVEPEER = ILivepeerBondingManager(0x35Bcf3c30594191d53231E4FF333E8A770453e40);
    ILivepeerRoundsManager private constant LIVEPEER_ROUNDS = ILivepeerRoundsManager(0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f);
    ERC20 private constant LPT = ERC20(0x289ba1701C2F088cf0faf8B3705246331cB8A839);
    IWETH9 private constant WETH = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ISwapRouter private constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    uint24 private constant UNISWAP_POOL_FEE = 10_000;

    function previewDeposit(uint256 assets) public pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) public view returns (uint256 amount) {
        (amount,) = LIVEPEER.getDelegatorUnbondingLock(msg.sender, unlockID);
    }

    function unlockMaturity(uint256 unlockID) public view returns (uint256 maturity) {
        // calculate unlock maturity in block number
        // in Livepeer this is expressed in rounds with a fixed amount of blocks
        // roundLength = n
        // currentRound = r
        // withdrawRound = w
        // blockRemainingInCurrentRound = b = roungLength - (block.number - currentRoundStartBlock)
        // maturity = n*(w - r - 1) + b
        (, uint256 withdrawRound) = LIVEPEER.getDelegatorUnbondingLock(msg.sender, unlockID);
        uint256 currentRound = LIVEPEER_ROUNDS.currentRound();
        uint256 roundLength = LIVEPEER_ROUNDS.roundLength();
        uint256 currentRoundStartBlock = LIVEPEER_ROUNDS.currentRoundStartBlock();
        uint256 blockRemainingInCurrentRound = roundLength - (block.number - currentRoundStartBlock);
        if (withdrawRound > currentRound) {
            maturity = roundLength * (withdrawRound - currentRound - 1) + blockRemainingInCurrentRound;
        }
    }

    function getTotalStaked(address /*validator*/ ) public view returns (uint256) {
        return LIVEPEER.pendingStake(msg.sender, 0);
    }

    function stake(address validator, uint256 amount) public {
        LPT.approve(address(LIVEPEER), amount);
        LIVEPEER.bond(amount, validator);
    }

    function unstake(address, /*validator*/ uint256 amount) public returns (uint256 unlockID) {
        // returns the *next* Livepeer unbonding lock ID for the delegator
        // this will be the `unlockID` after calling unbond
        (,,,,,, unlockID) = LIVEPEER.getDelegator(address(this));
        LIVEPEER.unbond(amount);
    }

    function withdraw(address, /*validator*/ uint256 unlockID) public {
        LIVEPEER.withdrawStake(unlockID);
    }

    function claimRewards(address validator, uint256) public returns (uint256 newStake) {
        _livepeerClaimFees();

        // restake
        uint256 amount = LPT.balanceOf(address(this));
        if (amount != 0) {
            stake(validator, amount);
        }

        // Read new stake
        newStake = LIVEPEER.pendingStake(address(this), 0);
    }

    /// @notice function for swapping ETH fees to LPT
    function _livepeerClaimFees() internal {
        // get pending fees
        uint256 pendingFees;
        if ((pendingFees = LIVEPEER.pendingFees(address(this), 0)) == 0) return;
        // withdraw fees
        LIVEPEER.withdrawFees(payable(address(this)), pendingFees);
        // convert fees to WETH
        WETH.deposit{ value: address(this).balance }();
        ERC20(address(WETH)).safeApprove(address(UNISWAP_ROUTER), address(this).balance);
        // Create initial params for swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(address(LPT)),
            fee: UNISWAP_POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: address(this).balance,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });

        // make a static call to see how much LPT would be received
        // yes but that's from the static call, true comes from staticcall, and the returndata into returnData, that's the mocked
        // response
        // if you make the call revert then success would be false
        // :)
        (bool success, bytes memory returnData) = //ok i'll try this
         address(UNISWAP_ROUTER).staticcall(abi.encodeWithSelector(UNISWAP_ROUTER.exactInputSingle.selector, params));

        if (!success) return;

        // set return value of staticcall to minimum LPT value to receive from swap
        params.amountOutMinimum = abi.decode(returnData, (uint256));

        // execute swap
        UNISWAP_ROUTER.exactInputSingle(params);
    }
}
