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
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { Adapter, AdapterDelegateCall } from "core/adapters/Adapter.sol";
import { Router } from "core/router/Router.sol";
import { TenderizerImmutableArgs, TenderizerErrors, TenderizerEvents, TenderizerStorage } from "core/tenderizer/TenderizerBase.sol";
import { TToken } from "core/tendertoken/TToken.sol";

// TODO: Fees
// Fees MUST update the totalSupply and totalShares when minting
// TODO: Claim rewards
// Figure out a good way to handle claiming rewards
// TODO: Rebase automation
// Automate claiming rewards, figure out a good solution

/// @title Tenderizer
/// @notice Liquid Staking vault using fixed-point math with full type safety and unstructured storage
/// @dev Delegates calls to a stateless Adapter contract which is responsible for interacting with a third-party staking protocol

contract Tenderizer is TenderizerImmutableArgs, TenderizerStorage, TenderizerErrors, TenderizerEvents, TToken {
  using AdapterDelegateCall for Adapter;
  using FixedPointMathLib for uint256;
  using SafeTransferLib for ERC20;

  function name() public view override returns (string memory) {
    return string(abi.encodePacked("tender", ERC20(asset()).symbol(), " ", validator()));
  }

  function symbol() public view override returns (string memory) {
    return string(abi.encodePacked("t", ERC20(asset()).symbol(), "_", validator()));
  }

  function previewDeposit(uint256 assets) public view returns (uint256) {
    return _adapter().previewDeposit(assets);
  }

  function unlockMaturity(uint256 unlockID) public view returns (uint256) {
    return _adapter().unlockMaturity(unlockID);
  }

  function previewWithdraw(uint256 unlockID) public view returns (uint256) {
    return _adapter().previewWithdraw(unlockID);
  }

  function deposit(address receiver, uint256 assets) public returns (uint256) {
    // transfer tokens before minting (or ERC777's could re-enter)
    ERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

    // preview deposit to get actual assets to mint for
    // deducts any possible third-party protocol taxes or fees
    uint256 actualAssets = previewDeposit(assets);

    // stake assets
    _stake(validator(), assets);

    // mint tokens to receiver
    _mint(receiver, actualAssets);

    // get *exact* tToken output amount
    // can be different from `actualAssets` due to rounding
    uint256 tTokenOut = balanceOf(receiver);
    // emit Deposit event
    emit Deposit(msg.sender, receiver, assets, tTokenOut);

    return tTokenOut;
  }

  function unlock(uint256 assets) public returns (uint256 unlockID) {
    // burn tTokens before creating an `unlock`
    _burn(msg.sender, assets);

    // unlock assets and get unlockID
    unlockID = _unstake(validator(), assets);

    // create unlock of unlockID
    _unlocks().createUnlock(msg.sender, unlockID);

    // emit Unlock event
    emit Unlock(msg.sender, assets, unlockID);
  }

  function withdraw(address receiver, uint256 unlockID) public returns (uint256) {
    // retrieve amount of assets withdrawable for `unlockID`
    uint256 assets = previewWithdraw(unlockID);

    // Redeem unlock if mature
    _unlocks().useUnlock(msg.sender, unlockID);

    // withdraw assets to send to `receiver`
    _withdraw(validator(), unlockID);

    // transfer assets to `receiver`
    ERC20(asset()).safeTransfer(receiver, assets);

    // emit Withdraw event
    emit Withdraw(receiver, assets, unlockID);

    return assets;
  }

  function _stake(address validator, uint256 amount) internal {
    _adapter()._delegatecall(abi.encodeWithSelector(_adapter().stake.selector, validator, amount));
  }

  function _unstake(address validator, uint256 amount) internal returns (uint256 unlockID) {
    unlockID = abi.decode(
      _adapter()._delegatecall(abi.encodeWithSelector(_adapter().stake.selector, validator, amount)),
      (uint256)
    );
  }

  function _withdraw(address validator, uint256 unlockID) internal {
    _adapter()._delegatecall(abi.encodeWithSelector(_adapter().withdraw.selector, validator, unlockID));
  }

  function _adapter() internal view returns (Adapter) {
    return Adapter(Router(_router()).adapter(asset()));
  }
}