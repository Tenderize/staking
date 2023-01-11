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

import { Clone } from "clones/Clone.sol";

pragma solidity 0.8.17;

abstract contract VaultBase is Clone {
  function owner() public pure returns (address) {
    return _getArgAddress(0); //ends at 20
  }

  function asset() public pure virtual returns (address) {
    return _getArgAddress(20); //ends at 40
  }

  function validator() public pure virtual returns (address) {
    return _getArgAddress(40); // ends at 60
  }
}
