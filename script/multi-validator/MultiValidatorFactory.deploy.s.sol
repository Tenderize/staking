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

import { MultiValidatorFactory } from "core/multi-validator/Factory.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Script, console2 } from "forge-std/Script.sol";

import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

contract MultiValidatorFactory_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));
    MultiValidatorFactory factory;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privKey);
        console2.log("Deploying MultiValidatorFactory...");
        address factoryImpl = address(new MultiValidatorFactory());
        factory = MultiValidatorFactory(address(new ERC1967Proxy{ salt: salt }(address(factoryImpl), "")));
        factory.initialize();
        console2.log("MultiValidatorFactory deployed at: %s", address(factory));

        // deploy flash unstake wrapper
        address flashUnstake = address(new FlashUnstake());
        console2.log("FlashUnstake deployed at: %s", flashUnstake);

        vm.stopBroadcast();
    }
}
