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
import { IWETH9 } from "core/interfaces/IWETH9.sol";
import { ISwapRouter } from "core/interfaces/ISwapRouter.sol";
import { Tenderizer, Adapter } from "core/tenderizer/Tenderizer.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

pragma solidity 0.8.17;

interface ILivepeerBondingManager {
  function bond(uint256 _amount, address _to) external;

  function unbond(uint256 _amount) external;

  function withdrawStake(uint256 _unbondingLockId) external;

  function withdrawFees(address payable, uint256) external;

  function pendingFees(address _delegator, uint256 _endRound) external view returns (uint256);

  function pendingStake(address _delegator, uint256 _endRound) external view returns (uint256);

  function getDelegator(
    address _delegator
  )
    external
    view
    returns (
      uint256 bondedAmount,
      uint256 fees,
      address delegateAddress,
      uint256 delegatedAmount,
      uint256 startRound,
      uint256 lastClaimRound,
      uint256 nextUnbondingLockId
    );

  function getDelegatorUnbondingLock(
    address _delegator,
    uint256 _unbondingLockId
  ) external view returns (uint256 amount, uint256 withdrawRound);
}

interface ILivepeerRoundsManager {
  function currentRound() external view returns (uint256);

  function currentRoundStartBlock() external view returns (uint256);

  function roundLength() external view returns (uint256);
}

contract LivepeerAdapter {
  using SafeTransferLib for ERC20;
  ILivepeerBondingManager livepeer;
  ILivepeerRoundsManager livepeerRounds;
  ERC20 LPT;
  IWETH9 weth;
  ISwapRouter uniswapRouter;
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

  function unstake(address validator, uint256 amount) public returns (uint256 unlockID) {
    // returns the *next* Livepeer unbonding lock ID for the delegator
    // this will be the unlockID after calling unbond
    (, , , , , , unlockID) = livepeer.getDelegator(address(this));
    livepeer.unbond(amount);
  }

  function withdraw(address /*validator*/, uint256 unlockID) public {
    livepeer.withdrawStake(unlockID);
  }

  function claimRewards() public {
    uint256 pendingFees;
    if ((pendingFees = livepeer.pendingFees(address(this), 0)) != 0) {
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

      // set return value of staticcall to minimum LPT value to receive from swap
      params.amountOutMinimum = abi.decode(returnData, (uint256));

      // execute swap
      uint256 amountOut = uniswapRouter.exactInputSingle(params);

      // should we restake here ?
      // how should we generalise adapter returns here ? int256 rewards ?
    }
  }
}
