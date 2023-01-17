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
 * @title Vault
 * @notice Gas efficient base implementation for a Liquid Staking Vault using fixed-point math with full type safety
 * @author Tenderize (https://github.com/tenderize)
 */

pragma solidity 0.8.17;

// import { UD60x18 } from "math/UD60x18.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { VaultStorage } from "core/vault/VaultStorage.sol";
import { VaultBase } from "core/vault/VaultBase.sol";

contract Vault is VaultStorage, VaultBase, TToken {
  using FixedPointMathLib for uint256;
  using SafeTransferLib for ERC20;

  event Deposit(address indexed sender, address indexed receiver, uint256 assets);

  event Unlock(address indexed receiver, uint256 assets);

  event Withdraw(address indexed receiver, uint256 assets);

  error ZeroShares();

  error OnlyOwner(address owner, address caller);

  modifier onlyOwner() {
    checkOwner();
    _;
  }

  function checkOwner() internal view {
    if (msg.sender != owner()) revert OnlyOwner(owner(), msg.sender);
  }

  function name() public view override returns (string memory) {
    return string(abi.encodePacked("tender", ERC20(asset()).symbol(), " ", validator()));
  }

  function symbol() public view override returns (string memory) {
    return string(abi.encodePacked("t", ERC20(asset()).symbol(), "_", validator()));
  }

  function totalAssets() public view returns (uint256) {
    VaultData storage s = _loadVaultSlot();
    return s.totalAssets;
  }

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

  function setTotalAssets(uint256 assets) public onlyOwner {
    _loadVaultSlot().totalAssets = assets;
  }

  function deposit(address receiver, uint256 assets) public onlyOwner returns (uint256 shares) {
    // calculate shares for assets
    // check for rounding error
    if ((shares = convertToShares(assets)) == 0) revert ZeroShares();

    // transfer tokens before minting (or ERC777's could re-enter)
    // TODO: consider making this a transferFrom receiver and let user approve vault instead of Tenderizer
    ERC20(asset()).safeTransferFrom(receiver, address(this), assets);
    // mint shares
    _mint(receiver, shares);
    // add to total assets
    _loadVaultSlot().totalAssets += assets;
    // emit deposit event
    emit Deposit(msg.sender, receiver, assets);
    // **stake tokens**
  }

  // If unlock and withdraw deals with another
  // "class" e.g. withdrawalPools
  // then maybe we should consider it outside of scope
  // of the LS vault and only concern the LSVault with accounting
  // and transferring tokens
  function unlock(address owner, uint256 assets) public onlyOwner returns (uint256 shares) {
    // calculate shares to burn
    // check rounding error
    if ((shares = convertToShares(assets)) == 0) revert ZeroShares();
    // burn shares
    _burn(owner, shares);
    // decrease total assets
    _loadVaultSlot().totalAssets -= assets;
    // emit event
    emit Unlock(owner, assets);
    // **unstake tokens**
  }

  // Can we maybe have the withdraw function receive the NFT from receiver instead
  // The Tenderizer does all the stuff on how to actually redeem the NFT and calculate the output assets from the vault to send
  // The vault then burns the NFT instead of the Tenderizer
  function withdraw(address receiver, uint256 assets) public onlyOwner {
    // **NFT lock is redeemed**
    // **withdraw tokens**

    // transfer tokens to receiver
    ERC20(asset()).safeTransfer(receiver, assets);
    // emit event
    emit Withdraw(receiver, assets);
  }
}
