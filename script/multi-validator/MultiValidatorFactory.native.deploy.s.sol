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

        //  deploy flash unstake wrapper
        address flashUnstake = address(new FlashUnstake());
        console2.log("FlashUnstake deployed at: %s", flashUnstake);

        vm.stopBroadcast();
    }
}

/* 
  Registry Implementation:  0x4F1728d4aFE52a6B581FD139f47A56021cE09772
  Registry Proxy:  0x4EB2ce452ea35A050495c3c23193b385f48473C0
  Renderer Implementation:  0x185c39C27b4d55FB665c6f72734f13B67225114B
  Renderer Proxy:  0x79a8e10Ce1aA4eBAa00c469593aA550C0f11E6a2
  Unlocks:  0x5dDADBA4a7C5794441F2536b826a9660d9F93095
  Tenderizer Implementation:  0x61FCAF26fF11CE1b5b372E3Dae96640F0B932cEa
  Factory (Beacon):  0xf8292992Ac9cFa7524DA04C63E4d296A4a81C887
  


  Deploying MultiValidatorFactory...
  MultiValidatorFactory deployed at: 0xe6c969743180BE1AdC8Fd8880DBEFef41412dae1
  FlashUnstake deployed at: 0xDEaa38CeA8048A7aaEC81F0081c0aA38A972BBB5

 MultiValidator SEI deployed At: 0x58CDD57FD0c878AF54eD0D9578959BA8FD154Aa7

  */
