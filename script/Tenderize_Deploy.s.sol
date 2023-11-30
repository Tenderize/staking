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
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Registry } from "core/registry/Registry.sol";
import { FACTORY_ROLE } from "core/registry/Roles.sol";
import { Renderer } from "core/unlocks/Renderer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Factory } from "core/factory/Factory.sol";

contract Tenderize_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = bytes32(uint256(1));

    function run() public {
        string memory json_output;

        // Start broadcasting with private key from `.env` file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Registry (without initialization)
        // - Deploy Registry Implementation
        Registry registry = new Registry{salt: salt}();
        vm.serializeAddress(json_output, "registry_implementation", address(registry));
        // - Deploy Registry UUPS Proxy
        address registryProxy = address(new ERC1967Proxy{salt: salt}(address(registry), ""));
        vm.serializeAddress(json_output, "registry_proxy", registryProxy);
        console2.log("Registry Implementation: ", address(registry));
        console2.log("Registry Proxy: ", registryProxy);

        // 2. Deploy Unlocks
        // - Deploy Renderer Implementation
        Renderer renderer = new Renderer{salt: salt}();
        vm.serializeAddress(json_output, "renderer_implementation", address(renderer));
        // - Deploy Renderer UUPS Proxy
        ERC1967Proxy rendererProxy = new ERC1967Proxy{salt: salt}(address(renderer), abi.encodeCall(renderer.initialize, ()));
        vm.serializeAddress(json_output, "renderer_proxy", address(rendererProxy));
        // - Deploy Unlocks
        Unlocks unlocks = new Unlocks{salt: salt}(address(registryProxy), address(rendererProxy));
        vm.serializeAddress(json_output, "unlocks", address(unlocks));
        console2.log("Renderer Implementation: ", address(renderer));
        console2.log("Renderer Proxy: ", address(rendererProxy));
        console2.log("Unlocks: ", address(unlocks));

        // 3. Deploy Tenderizer Implementation
        Tenderizer tenderizer = new Tenderizer{salt: salt}(registryProxy, address(unlocks));
        vm.serializeAddress(json_output, "tenderizer_implementation", address(tenderizer));
        console2.log("Tenderizer Implementation: ", address(tenderizer));

        // 4. Initialize Registry
        Registry(registryProxy).initialize(address(tenderizer), address(unlocks));

        // 5. Deploy Factory
        Factory factory = new Factory{salt: salt}(address(registryProxy));
        vm.serializeAddress(json_output, "factory", address(factory));
        // - Grant Factory role to Factory
        Registry(registryProxy).grantRole(FACTORY_ROLE, address(factory));
        console2.log("Factory: ", address(factory));

        vm.stopBroadcast();

        // Write json_output to file
        vm.writeJson(json_output, "deployments.json");
    }
}
