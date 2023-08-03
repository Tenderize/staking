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
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Factory } from "core/factory/Factory.sol";

contract XYZ_Data is Script {
    bytes32 private constant salt = 0x0;

    function run() public {
        MockERC20 XYZ = MockERC20(0xed9358918089a858d0af58AC63c93699a67B6b91);

        uint256 privKey = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(privKey);
        vm.startBroadcast(privKey);

        XYZ.mint(me, 10_000_000_000 ether);
        address tenderizer_1 = 0x6f674B27fE58740f14754a34ccd6C636646FA755;
        address tenderizer_2 = 0x3186a94AA139f420228Bc73D68b448be52bC4106;
        address tenderizer_3 = 0x2554110E3b2Ad09f0ba7D9392c9845592F55B1E8;
        XYZ.approve(tenderizer_1, 10_000_000_000 ether);
        XYZ.approve(tenderizer_2, 10_000_000_000 ether);
        XYZ.approve(tenderizer_3, 10_000_000_000 ether);

        Tenderizer(tenderizer_1).deposit(me, 35_983 ether);
        Tenderizer(tenderizer_2).deposit(me, 12_821 ether);
        Tenderizer(tenderizer_3).deposit(me, 5123 ether);

        Tenderizer(tenderizer_1).unlock(1202 ether);
    }
}
