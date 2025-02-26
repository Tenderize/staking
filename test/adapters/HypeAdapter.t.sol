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

pragma solidity >=0.8.25;

import { Test, console2 } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { HypeAdapter } from "core/tenderize-v3/Hyperliquid/HypeAdapter.sol";

contract HypeAdapterTest is Test {
    HypeAdapter adapter;

    function setUp() public {
        vm.startPrank(0x3C83a5CaE32a05e88CA6A0350edb540194851a76);
        // vm.createSelectFork(vm.envString("HYPERLIQUID_RPC"));
        adapter = new HypeAdapter();
        console2.log("Adapter deployed at: %s", address(adapter));
        vm.stopPrank();
    }

    function test_rebase() public {
        vm.startPrank(0x3C83a5CaE32a05e88CA6A0350edb540194851a76);

        uint256 newStake = adapter.rebase(bytes32(bytes20(0x3C83a5CaE32a05e88CA6A0350edb540194851a76)), 0);
        console2.log("New stake %s", newStake);
        vm.stopPrank();
    }
}
