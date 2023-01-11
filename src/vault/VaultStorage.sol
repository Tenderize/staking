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

abstract contract VaultStorage {
  uint256 private constant VAULT_SLOT = uint256(keccak256("xyz.tenderize.vault.storage.location")) - 1;

  struct VaultData {
    uint256 totalAssets;
  }

  function _loadVaultSlot() internal pure returns (VaultData storage s) {
    uint256 slot = VAULT_SLOT;

    // solhint-disable-next-line no-inline-assembly
    assembly {
      s.slot := slot
    }
  }
}
