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

import { Script, console2 } from "forge-std/Script.sol";

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { Registry } from "core/registry/Registry.sol";

contract MultiValidatorLST_Upgrade is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    function run() public {
        uint256 privateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privateKey);

        MultiValidatorLST lst = new MultiValidatorLST{ salt: salt }(Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE));
        console2.log("MultiValidatorLST deployed at: %s", address(lst));

        vm.stopBroadcast();
    }
}
