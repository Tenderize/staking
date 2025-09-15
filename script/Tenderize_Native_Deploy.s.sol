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

import { Tenderizer } from "core/tenderize-v3/Tenderizer.sol";
import { TenderizerFactory } from "core/tenderize-v3/Factory.sol";
import { Registry } from "core/tenderize-v3/registry/Registry.sol";
import { FACTORY_ROLE } from "core/registry/Roles.sol";
import { Renderer } from "core/unlocks/Renderer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";

uint256 constant VERSION = 1;

contract Tenderize_Native_Deploy is Script {
    // Contracts are deployed deterministically using CREATE2 via forge`s deterministic-deployment-proxy.
    bytes32 private constant salt = bytes32(VERSION);

    function run() public {
        string memory json_output;

        // Start broadcasting with private key from `.env` file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy Registry (without initialization)
        Registry registryImpl = new Registry();
        address registryProxy = address(new ERC1967Proxy(address(registryImpl), ""));
        vm.serializeAddress(json_output, "registry_implementation", address(registryImpl));
        vm.serializeAddress(json_output, "registry_proxy", registryProxy);
        console2.log("Registry Implementation: ", address(registryImpl));
        console2.log("Registry Proxy: ", registryProxy);

        // 2. Deploy Unlocks
        // - Deploy Renderer Implementation
        Renderer rendererImpl = new Renderer();
        vm.serializeAddress(json_output, "renderer_implementation", address(rendererImpl));
        // - Deploy Renderer UUPS Proxy
        ERC1967Proxy rendererProxy = new ERC1967Proxy(address(rendererImpl), abi.encodeCall(rendererImpl.initialize, ()));
        vm.serializeAddress(json_output, "renderer_proxy", address(rendererProxy));
        // - Deploy Unlocks
        Unlocks unlocks = new Unlocks(registryProxy, address(rendererProxy));
        vm.serializeAddress(json_output, "unlocks", address(unlocks));
        console2.log("Renderer Implementation: ", address(rendererImpl));
        console2.log("Renderer Proxy: ", address(rendererProxy));
        console2.log("Unlocks: ", address(unlocks));

        // 3. Deploy Tenderizer Implementation (native asset)
        address asset = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE; // Native ETH
        Tenderizer tenderizerImpl = new Tenderizer(asset, registryProxy, address(unlocks));
        vm.serializeAddress(json_output, "tenderizer_implementation", address(tenderizerImpl));
        console2.log("Tenderizer Implementation: ", address(tenderizerImpl));

        // 4. Initialize Registry
        Registry(registryProxy).initialize(address(tenderizerImpl), address(unlocks));
        Registry(registryProxy).setTreasury(address(payable(msg.sender)));

        // 5. Deploy TenderizerFactory (UpgradeableBeacon) and register it
        TenderizerFactory factory = new TenderizerFactory(registryProxy, address(tenderizerImpl));
        vm.serializeAddress(json_output, "factory", address(factory));
        console2.log("Factory (Beacon): ", address(factory));

        // - Grant FACTORY_ROLE to Factory
        Registry(registryProxy).grantRole(FACTORY_ROLE, address(factory));

        vm.stopBroadcast();

        // Write json_output to file if desired
        // vm.writeJson(json_output, "deployments_native.json");
    }
}
