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
  ILivepeerBondingManager private constant livepeer = ILivepeerBondingManager(address(0));
  ILivepeerRoundsManager private constant livepeerRounds = ILivepeerRoundsManager(address(0));
  ERC20 private constant LPT = ERC20(address(0));
  IWETH9 private constant weth = IWETH9(address(0));
  ISwapRouter private constant uniswapRouter = ISwapRouter(address(0));
  uint24 private constant UNISWAP_POOL_FEE = 10000;

  function previewDeposit(uint256 assets) public pure returns (uint256) {
    return assets;
  }

  function previewWithdraw(uint256 unlockID) public view returns (uint256 amount) {
    (amount, ) = livepeer.getDelegatorUnbondingLock(address(this), unlockID);
  }

  function unlockMaturity(uint256 unlockID) public view returns (uint256 maturity) {
    // calculate unlock maturity in block number
    // in Livepeer this is expressed in rounds with a fixed amount of blocks
    // roundLength = n
    // currentRound = r
    // withdrawRound = w
    // blockRemainingInCurrentRound = b = roungLength - (block.number - currentRoundStartBlock)
    // maturity = n*(w - r - 1) + b
    (, uint256 withdrawRound) = livepeer.getDelegatorUnbondingLock(address(this), unlockID);
    uint256 currentRound = livepeerRounds.currentRound();
    uint256 roundLength = livepeerRounds.roundLength();
    uint256 currentRoundStartBlock = livepeerRounds.currentRoundStartBlock();
    uint256 blockRemainingInCurrentRound = roundLength - (block.number - currentRoundStartBlock);
    maturity = roundLength * (withdrawRound - currentRound - 1) + blockRemainingInCurrentRound;
  }

  function getTotalStaked(address validator) public view returns (uint256) {
    return livepeer.pendingStake(validator, 0);
  }

  function stake(address validator, uint256 amount) public {
    LPT.approve(address(livepeer), amount);
    livepeer.bond(amount, validator);
  }

  function unstake(address /*validator*/, uint256 amount) public returns (uint256 unlockID) {
    // returns the *next* Livepeer unbonding lock ID for the delegator
    // this will be the `unlockID` after calling unbond
    (, , , , , , unlockID) = livepeer.getDelegator(address(this));
    livepeer.unbond(amount);
  }

  function withdraw(address /*validator*/, uint256 unlockID) public {
    livepeer.withdrawStake(unlockID);
  }

  function claimRewards(address validator, uint256 currentStake) public returns (uint256 newStake) {
    _livepeerClaimFees();

    // restake
    uint256 amount = LPT.balanceOf(address(this));
    if (amount != 0) {
      stake(validator, amount);
    }

    // Read new stake
    newStake = getTotalStaked(validator);
  }

  /// @notice function for swapping livepeer fees to LPT
  function _livepeerClaimFees() internal {
    // get pending fees
    uint256 pendingFees;
    if ((pendingFees = livepeer.pendingFees(address(this), 0)) == 0) return;
    // withdraw fees
    livepeer.withdrawFees(payable(address(this)), pendingFees);
    // convert fees to WETH
    weth.deposit{ value: address(this).balance }();
    ERC20(address(weth)).safeApprove(address(uniswapRouter), address(this).balance);
    // Create initial params for swap
    ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
      tokenIn: address(weth),
      tokenOut: address(address(LPT)),
      fee: UNISWAP_POOL_FEE,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: address(this).balance,
      amountOutMinimum: 0,
      sqrtPriceLimitX96: 0
    });

    // make a static call to see how much LPT would be received
    (bool success, bytes memory returnData) = address(uniswapRouter).staticcall(
      abi.encodeWithSelector(uniswapRouter.exactInputSingle.selector, params)
    );

    if (!success) return;

    // set return value of staticcall to minimum LPT value to receive from swap
    params.amountOutMinimum = abi.decode(returnData, (uint256));

    // execute swap
    uniswapRouter.exactInputSingle(params);
  }
}
