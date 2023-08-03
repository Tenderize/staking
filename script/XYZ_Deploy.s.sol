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

pragma solidity >=0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { StakingXYZ } from "../test/helpers/StakingXYZ.sol";
import { XYZAdapter } from "../test/helpers/XYZAdapter.sol";
import { Registry } from "core/registry/Registry.sol";

import { Factory } from "core/factory/Factory.sol";

contract XYZ_Deploy is Script {
    bytes32 private constant salt = 0x0;

    function run() public {
        address registry = vm.envAddress("REGISTRY");
        address factory = vm.envAddress("FACTORY");

        vm.startBroadcast(vm.envUint("PRIVATE_KEY"));

        MockERC20 XYZ = new MockERC20{salt: salt}("XYZ", "XYZ", 18);
        console2.log("XYZ Token: ", address(XYZ));
        StakingXYZ stakingXYZ = new StakingXYZ{salt: salt}(address(XYZ));
        console2.log("StakingXYZ: ", address(stakingXYZ));
        XYZAdapter adapter = new XYZAdapter{salt: salt}(address(stakingXYZ), address(XYZ));
        console2.log("XYZ Adapter: ", address(adapter));
        // Register XYZ adapter
        Registry(registry).registerAdapter(address(XYZ), address(adapter));

        // Register some mock validators
        address[] memory validators = new address[](3);
        validators[0] = 0x597aD7F7A1C9F8d0121a9e949Cca7530F2B25ef6;
        validators[1] = 0x6C06d3246FbB77C4Ad75480E03d2a0A8eaF68121;
        validators[2] = 0xf909aC60C647a14DB3663dA5EcF5F8eCbE324395;

        for (uint256 i = 0; i < validators.length; i++) {
            Factory(factory).newTenderizer(address(XYZ), validators[i]);
        }
    }
}
