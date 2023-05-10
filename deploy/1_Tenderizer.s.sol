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

/*
Run:
source env
forge script deploy/1_Tenderizer.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify
*/

pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "core/factory/Factory.sol";
import "core/registry/Registry.sol";
import "core/tenderizer/Tenderizer.sol";
import "core/unlocks/Renderer.sol";
import "core/unlocks/Unlocks.sol";

contract Deploy is Script {
    bytes32 private constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Registry registryImpl = new Registry();
        bytes memory data = abi.encodeWithSignature("initialize()");
        Registry registry = Registry(address(new ERC1967Proxy(address(registryImpl), data)));

        address rendererImpl = address(new Renderer());
        address renderer = address(new ERC1967Proxy(rendererImpl, abi.encodeWithSignature("initialize()")));
        address unlocks = address(new Unlocks(address(registry), renderer));

        address tenderizerImpl = address(new Tenderizer());
        address factory = address(new Factory(address(registry), tenderizerImpl, unlocks));
        registry.grantRole(FACTORY_ROLE, address(factory));

        // TODO: Swap

        vm.stopBroadcast();

        console2.log("Registry Proxy: %s", address(registry));
        console2.log("Registry Impl: %s", address(registryImpl));
        console2.log("---------------------");
        console2.log("Tenderizer Impl: %s", address(tenderizerImpl));
        console2.log("Renderer Impl: %s", address(rendererImpl));
        console2.log("Renderer Proxy: %s", address(renderer));
        console2.log("Unlocks: %s", address(unlocks));
        console2.log("Tenderizer Factory created and registered at: %s", address(factory));
    }
}
