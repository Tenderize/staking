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

pragma solidity ^0.8.25;

import { UpgradeableBeacon } from "openzeppelin-contracts/proxy/beacon/UpgradeableBeacon.sol";

import { BeaconProxy } from "openzeppelin-contracts/proxy/beacon/BeaconProxy.sol";

import { Adapter } from "core/tenderize-v3/Adapter.sol";
import { Registry } from "core/tenderize-v3/registry/Registry.sol";
import { Tenderizer } from "core/tenderize-v3/Tenderizer.sol";

contract TenderizerFactory is UpgradeableBeacon {
    error InvalidAsset(address asset);
    error NotValidator(bytes32 validator);

    address public immutable registry;

    constructor(address _registry, address _implementation) UpgradeableBeacon(_implementation) {
        registry = _registry;
    }

    function createTenderizer(address asset, bytes32 validator) external payable returns (address tenderizer) {
        Adapter adapter = Adapter(Registry(registry).adapter(asset));

        if (address(adapter) == address(0)) revert InvalidAsset(asset);
        if (!adapter.isValidator(validator)) revert NotValidator(validator);
        tenderizer = address(new BeaconProxy(address(this), ""));
        // abi.encodeCall(Tenderizer.initialize, (validator)))
        Tenderizer(tenderizer).initialize(validator);
        Registry(registry).registerTenderizer(asset, validator, tenderizer);
    }
}
