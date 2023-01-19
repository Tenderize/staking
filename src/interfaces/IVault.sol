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

interface IVault {
  event Deposit(address indexed sender, address indexed receiver, uint256 assets);

  event Unlock(address indexed receiver, uint256 assets);

  event Withdraw(address indexed receiver, uint256 assets);

  error ZeroShares();

  error OnlyOwner(address owner, address caller);

  function asset() external view returns (address);

  function validator() external view returns (address);

  function convertToAssets(uint256 shares) external view returns (uint256);

  function convertToShares(uint256 assets) external view returns (uint256);

  function deposit(address receiver, uint256 assets) external;

  function unlock(address receiver, uint256 assets) external;

  function withdraw(address receiver, uint256 assets) external;
}
