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

// solhint-disable no-console

pragma solidity >=0.8.19;

import { Script, console2 } from "forge-std/Script.sol";

import { MultiValidatorLSTNative } from "core/tenderize-v3/multi-validator/MultiValidatorLST.sol";
import { MultiValidatorFactory } from "core/tenderize-v3/multi-validator/Factory.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    address[] tenderizers = [
        0x28D5bC07301472829bab14aC26CF74676e9FB1d3,
        0x9744581825e21C07F51B35BF3cC0AE9389a1Ca3C,
        0x131a09734AE656f78030b2a89687b4D58E2FbE62,
        0x9d68575fE6cA05E4D6F6d982fe6Dfac6678D243E
    ];

    MultiValidatorLSTNative lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        MultiValidatorFactory factory = MultiValidatorFactory(vm.envAddress("FACTORY"));
        vm.startBroadcast(privKey);

        console2.log("Deploying MultiValidatorLST...");

        lst = MultiValidatorLSTNative(payable(factory.deploy("SEI")));

        console2.log("MultiValidatorLST deployed at: %s", address(lst));

        lst.setFee(0.05e6); // 5% fee

        for (uint256 i = 0; i < tenderizers.length; i++) {
            lst.addValidator(payable(tenderizers[i]), 1_000_000 ether); // 2M Stake
        }

        vm.stopBroadcast();
    }
}
