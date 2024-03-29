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

pragma solidity >=0.8.19;

import { Tenderizer, Adapter } from "core/tenderizer/Tenderizer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Registry } from "core/registry/Registry.sol";

// solhint-disable func-name-mixedcase
// solhint-disable no-empty-blocks

contract TenderizerHarness is Tenderizer {
    constructor(address _registry, address _unlocks) Tenderizer(_registry, _unlocks) { }

    function exposed_registry() public view returns (Registry) {
        return _registry();
    }

    function exposed_unlocks() public view returns (Unlocks) {
        return _unlocks();
    }
}
