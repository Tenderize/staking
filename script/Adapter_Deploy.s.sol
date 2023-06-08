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

import { Script } from "forge-std/Script.sol";

import { Registry } from "core/registry/Registry.sol";

import { LivepeerAdapter } from "core/adapters/LivepeerAdapter.sol";
import { GraphAdapter } from "core/adapters/GraphAdapter.sol";

contract Adapter_Deploy is Script {
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy
    bytes32 private constant salt = 0x0;

    address private constant LPT = address(0x0);
    address private constant GRT = address(0x0);
    // address private constant MATIC = 0x0;

    function run() public {
        string memory json_output;

        // Start broadcasting with private key from `.env` file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Registry registry = Registry(vm.envAddress("REGISTRY"));
        address asset = vm.envAddress("ASSET");

        address adapter;

        // check which adapter to deploy
        if (asset == LPT) adapter = address(new LivepeerAdapter{salt: salt}());
        else if (asset == GRT) adapter = address(new GraphAdapter{salt: salt}());

        // register adapter
        registry.registerAdapter(asset, adapter);
    }
}
