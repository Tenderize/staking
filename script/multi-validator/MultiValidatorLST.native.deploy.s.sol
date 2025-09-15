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
        0x0BA49e1b6616CCb0650B39043554ad791b1b6eD1,
        0xCF4cD036Ac6FAB8F6bd49C0890ed53a38767B62F,
        0x06fd675BE0513d4fF5F05796a3BAD9d20d91610B,
        0x82c72F3Aefc525ade379b6E71E23f71e8fe84aab
    ];

    MultiValidatorLSTNative lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        MultiValidatorFactory factory = MultiValidatorFactory(0xe6c969743180BE1AdC8Fd8880DBEFef41412dae1);
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
