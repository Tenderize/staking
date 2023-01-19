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
  function asset() public pure returns (address) {
    return _getArgAddress(0); // start: 0 end: 19
  }

  function validator() public pure returns (address) {
    return _getArgAddress(20); // start: 20 end: 39
  }
}
