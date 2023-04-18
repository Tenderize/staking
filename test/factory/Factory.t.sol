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

import { Test, stdError } from "forge-std/Test.sol";

import { Factory } from "core/factory/Factory.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Registry } from "core/registry/Registry.sol";
import { Adapter } from "core/adapters/Adapter.sol";

// solhint-disable func-name-mixedcase
contract FactoryTest is Test {
    Factory private factory;

    Tenderizer private tenderizer = new Tenderizer();
    address private registry = vm.addr(1);
    address private unlocks = vm.addr(2);
    address private adapter = vm.addr(4);
    address private asset = vm.addr(4);
    address private validator = vm.addr(5);

    function setUp() public {
        factory = new Factory(registry, address(tenderizer), unlocks);
    }

    function test_InitialStorage() public {
        assertEq(factory.registry(), registry, "registry not set");
        assertEq(factory.unlocks(), unlocks, "unlocks not set");
        assertEq(factory.tenderizerImpl(), address(tenderizer), "tenderizer not set");
    }

    function test_NewTenderizer() public {
        vm.mockCall(registry, abi.encodeCall(Registry.adapter, (asset)), abi.encode(adapter));
        vm.mockCall(adapter, abi.encodeCall(Adapter.isValidator, (validator)), abi.encode(true));

        vm.expectCall(registry, abi.encodeCall(Registry.adapter, (asset)));
        // TODO: Assert call to registry
        // Since deployed tenderizer address cannot be pre-dertermined
        // we cannot make all the required assertions
        address newTenderizer = factory.newTenderizer(asset, validator);

        assertEq(Tenderizer(newTenderizer).asset(), asset, "asset not set");
        assertEq(Tenderizer(newTenderizer).validator(), validator, "validator not set");
    }

    function test_NewTenderizer_RevertIfNoAdapter() public {
        vm.mockCall(registry, abi.encodeCall(Registry.adapter, (asset)), abi.encode(address(0)));

        vm.expectCall(registry, abi.encodeCall(Registry.adapter, (asset)));
        vm.expectRevert(abi.encodeWithSelector(Factory.InvalidAsset.selector, asset));
        factory.newTenderizer(asset, validator);
    }

    function test_NewTenderizer_RevertIfNotValidator() public {
        vm.mockCall(registry, abi.encodeCall(Registry.adapter, (asset)), abi.encode(adapter));
        vm.mockCall(adapter, abi.encodeCall(Adapter.isValidator, (validator)), abi.encode(false));

        vm.expectCall(registry, abi.encodeCall(Registry.adapter, (asset)));
        vm.expectCall(adapter, abi.encodeCall(Adapter.isValidator, (validator)));
        vm.expectRevert(abi.encodeWithSelector(Factory.NotValidator.selector, validator));
        factory.newTenderizer(asset, validator);
    }
}
