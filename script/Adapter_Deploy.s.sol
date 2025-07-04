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

import { Script } from "forge-std/Script.sol";

import { Registry } from "core/registry/Registry.sol";

import { LivepeerAdapter, LPT, VERSION as LPT_VERSION } from "core/adapters/LivepeerAdapter.sol";
import { GraphAdapter, GRT, VERSION as GRT_VERSION } from "core/adapters/GraphAdapter.sol";
import { PolygonAdapter, POL, VERSION as POL_VERSION } from "core/adapters/PolygonAdapter.sol";
import { SeiAdapter, SEI, VERSION as SEI_VERSION } from "core/tenderize-v3/Sei/SeiAdapter.sol";

contract Adapter_Deploy is Script {
    uint256 VERSION;
    // Contracts are deployed deterministically.
    // e.g. `foo = new Foo{salt: salt}(constructorArgs)`
    // The presence of the salt argument tells forge to use https://github.com/Arachnid/deterministic-deployment-proxy

    // address private constant MATIC = 0x0;

    function run() public {
        // Start broadcasting with private key from `.env` file
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Registry registry = Registry(vm.envAddress("REGISTRY"));
        address asset = vm.envAddress("ASSET");

        address adapter;

        // check which adapter to deploy
        if (asset == address(LPT)) {
            adapter = address(new LivepeerAdapter{ salt: bytes32(LPT_VERSION) }());
        } else if (asset == address(GRT)) {
            adapter = address(new GraphAdapter{ salt: bytes32(GRT_VERSION) }());
        } else if (asset == address(POL)) {
            adapter = address(new PolygonAdapter{ salt: bytes32(POL_VERSION) }());
        } else if (asset == address(SEI)) {
            adapter = address(new SeiAdapter());
        } else {
            revert("Adapter not supported");
        }

        // register adapter
        // registry.registerAdapter(asset, adapter);
    }
}
