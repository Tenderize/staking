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

import { Unlocks } from "core/tenderizer/Unlocks.sol";
import { Vault } from "core/vault/Vault.sol";
import { Adapter, AdapterDelegateCall } from "core/tenderizer/Adapter.sol";

contract Tenderizer is Vault {
  using AdapterDelegateCall for Adapter;
  Adapter adapter;
  Unlocks unlocks;

  function previewDeposit(uint256 assets) public view returns (uint256) {
    return adapter.previewDeposit(assets);
  }

  function unlockMaturity(uint256 unlockID) public view returns (uint256) {
    return adapter.unlockMaturity(unlockID);
  }

  function previewWithdraw(uint256 unlockID) public view returns (uint256) {
    return adapter.previewWithdraw(unlockID);
  }

  function deposit(address receiver, uint256 assets) public override returns (uint256) {
    uint256 toMint = previewDeposit(assets);

    Vault.deposit(receiver, toMint);
    _stake(validator(), assets);

    return toMint;
  }

  function unlock(uint256 assets) public override returns (uint256 unlockID) {
    unlockID = _unstake(validator(), assets);
    unlocks.createUnlock(msg.sender, unlockID);

    Vault.unlock(assets);
  }

  function withdraw(address receiver, uint256 unlockID) public override returns (uint256) {
    uint256 assets = previewWithdraw(unlockID);

    _withdraw(validator(), unlockID);
    unlocks.useUnlock(receiver, unlockID);

    Vault.withdraw(receiver, assets);

    return assets;
  }

  function _stake(address validator, uint256 amount) internal {
    adapter._delegatecall(abi.encodeWithSelector(adapter.stake.selector, validator, amount));
  }

  function _unstake(address validator, uint256 amount) internal returns (uint256 unlockID) {
    unlockID = abi.decode(
      adapter._delegatecall(abi.encodeWithSelector(adapter.stake.selector, validator, amount)),
      (uint256)
    );
  }

  function _withdraw(address validator, uint256 unlockID) internal {
    adapter._delegatecall(abi.encodeWithSelector(adapter.withdraw.selector, validator, unlockID));
  }
}
