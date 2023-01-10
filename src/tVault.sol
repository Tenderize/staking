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

/**
 * @title tVault
 * @notice Gas efficient base implementation for a Liquid Staking Vault using fixed-point math with full type safety
 * @author Tenderize (https://github.com/tenderize)
 */

pragma solidity 0.8.17;

import { UD60x18 } from "math/UD60x18.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { tERC20 } from "./tERC20.sol";

// TODO: Interface
// TODO: tERC20

abstract contract tVault is tERC20 {
  using FixedPointMathLib for uint256;
  using SafeTransferLib for ERC20;

  event Deposit(address indexed sender, address indexed receiver, uint256 assets);

  event Withdraw(address indexed receiver, uint256 assets);

  function previewDeposit() public view virtual returns (uint256 shares) {}

  function asset() public view virtual returns (ERC20);

  function deposit(
    uint256 assets,
    address sender,
    address receiver
  ) public virtual returns (uint256 shares) {
    // calculate shares for assets
    // check for rounding error
    shares = convertToShares(assets);
    // transfer tokens before minting (or ERC777's could re-enter)
    // TODO: consider making this a transferFrom receiver and let user approve vault instead of Tenderizer
    asset().safeTransferFrom(msg.sender, address(this), assets);
    // mint shares
    _mint(receiver, shares);
    // emit deposit event
    emit Deposit(sender, receiver, assets);
    // **stake tokens**
  }

  // If unlock and withdraw deals with another
  // "class" e.g. withdrawalPools
  // then maybe we should consider it outside of scope
  // of the LS vault and only concern the LSVault with accounting
  // and transferring tokens
  function unlock(uint256 assets, address owner) public virtual returns (uint256 unlockID) {
    // calculate shares to burn
    // burn shares
    _burn(owner, convertToShares(assets));
    // emit event
    emit Withdraw(owner, assets);
    // **unstake tokens**
  }

  function withdraw(uint256 assets, address receiver) public virtual returns (uint256 received) {
    // **NFT lock is redeemed**
    // **withdraw tokens**
    // transfer tokens to receiver
    asset().safeTransfer(receiver, assets);
    // emit event
  }

  function totalAssets() public view virtual returns (uint256);

  function totalShares() public view returns (uint256) {
    ERC20Data storage s = _loadERC20Slot();
    return s._totalSupply;
  }

  function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
    uint256 _totalShares = totalShares(); // Saves an extra SLOAD if slot is non-zero
    return _totalShares == 0 ? shares : shares.mulDivDown(totalAssets(), _totalShares);
  }

  function convertToShares(uint256 assets) public view override returns (uint256 shares) {
    uint256 _totalShares = totalShares(); // Saves an extra SLOAD if slot is non-zero
    return _totalShares == 0 ? assets : assets.mulDivDown(_totalShares, totalAssets());
  }
}
