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

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { MultiValidatorFactory } from "core/multi-validator/Factory.sol";

import { LPT } from "core/adapters/LivepeerAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

address constant TENDERIZER_1 = 0x6CBC6967A941CCa12c1316E4D567c6892C3F0Ed6;
address constant TENDERIZER_2 = 0xFCfeD578958D42Cd1c2ea09db09bfC1A668E0efd;
address constant TENDERIZER_3 = 0x3A760477cA7CB37Dec4DF9B9e19ce15CB265bfF8;

address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    MultiValidatorFactory factory;
    MultiValidatorLST lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privKey);
        address me = vm.addr(privKey);

        console2.log("Deploying MultiValidatorFactory...");
        address factoryImpl = address(new MultiValidatorFactory(me));
        factory =
            MultiValidatorFactory(address(new ERC1967Proxy{ salt: bytes32("MultiValidatorLSTFactory") }(address(factoryImpl), "")));
        factory.initialize();

        console2.log("MultiValidatorFactory deployed at: %s", address(factory));
        console2.log("Factory owner: %s", factory.owner());

        console2.log("Deploying MultiValidatorLST...");

        lst = MultiValidatorLST(factory.deploy(address(LPT)));

        console2.log("MultiValidatorLST deployed at: %s", address(lst));

        lst.setFee(0.05e6); // 5% fee

        lst.addValidator(payable(TENDERIZER_1), 2_000_000 ether); // 3M Stake
        lst.addValidator(payable(TENDERIZER_2), 2_000_000 ether); // 2M Stake
        lst.addValidator(payable(TENDERIZER_3), 2_000_000 ether); // 1M Stake
        vm.stopBroadcast();
    }
}
