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

import { MultiValidatorFactory } from "core/tenderize-v3/multi-validator/Factory.sol";
import { Registry } from "core/tenderize-v3/registry/Registry.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { MultiValidatorLSTNative } from "core/tenderize-v3/multi-validator/MultiValidatorLST.sol";
import { UnstakeNFT } from "core/tenderize-v3/multi-validator/UnstakeNFT.sol";

import { Script, console2 } from "forge-std/Script.sol";

import { FlashUnstake } from "core/tenderize-v3/multi-validator/FlashUnstakeNative.sol";

contract MultiValidatorFactory_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));
    MultiValidatorFactory factory;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        address registry = vm.envAddress("REGISTRY");
        vm.startBroadcast(privKey);
        console2.log("Deploying MultiValidatorFactory...");
        MultiValidatorLSTNative initialImpl = new MultiValidatorLSTNative(Registry(registry));
        UnstakeNFT initialUnstakeNFTImpl = new UnstakeNFT();

        address factoryImpl = address(new MultiValidatorFactory(Registry(registry), initialImpl, initialUnstakeNFTImpl));
        factory = MultiValidatorFactory(address(new ERC1967Proxy(address(factoryImpl), "")));
        factory.initialize();
        console2.log("MultiValidatorFactory deployed at: %s", address(factory));

        // deploy flash unstake wrapper
        // address flashUnstake = address(new FlashUnstake());
        // console2.log("FlashUnstake deployed at: %s", flashUnstake);

        vm.stopBroadcast();
    }
}
