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

import { Tenderizer, Adapter } from "core/tenderizer/Tenderizer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";

// solhint-disable func-name-mixedcase

contract TenderizerHarness is Tenderizer {
    function exposed_adapter() public view returns (Adapter) {
        return _adapter();
    }

    function exposed_registry() public pure returns (address) {
        return _registry();
    }

    function exposed_unlocks() public pure returns (Unlocks) {
        return _unlocks();
    }
}
