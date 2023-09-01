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
        MockERC20 XYZ = MockERC20(0xf1C65dFa90eF3B6369f540bC32D7143cA4233c1e);

        uint256 privKey = vm.envUint("PRIVATE_KEY");
        address me = vm.addr(privKey);
        vm.startBroadcast(privKey);

        XYZ.mint(me, 10_000_000_000 ether);
        address tenderizer_1 = 0x35D2BC5Fc0884a7A24E9B1D723A4d99922d788EB;
        address tenderizer_2 = 0xD58Fed21106A046093086903909478AD96D310a8;
        address tenderizer_3 = 0x2eaC4210B90D13666f7E88635096BdC17C51FB70;
        XYZ.approve(tenderizer_1, 10_000_000_000 ether);
        XYZ.approve(tenderizer_2, 10_000_000_000 ether);
        XYZ.approve(tenderizer_3, 10_000_000_000 ether);

        Tenderizer(tenderizer_1).deposit(me, 35_983 ether);
        Tenderizer(tenderizer_2).deposit(me, 12_821 ether);
        Tenderizer(tenderizer_3).deposit(me, 5123 ether);

        Tenderizer(tenderizer_1).unlock(1202 ether);
    }
}
