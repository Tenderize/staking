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
import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

import { LPT } from "core/adapters/LivepeerAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    address[] tenderizers = [
        0x4b7339E599a599DBd7829a8ECA0d233ED4F7eA09,
        0xFB32bF22B4F004a088c1E7d69e29492f5D7CD7E1,
        0x6DFd5Cee0Ed2ec24Fdc814Ad857902DE01c065d6,
        0xbEb81a62E9A8463C22a3f999846F3E3FB2e2002A,
        0x3a3D463fb8241DA6051eb4DAB2200C8b99691315,
        0x109eA4859a99B3347db5025A920f63Ab0EF3de42,
        0x6CBC6967A941CCa12c1316E4D567c6892C3F0Ed6,
        0xFBc4435A3CebC1F4bd9c56aC95cfA37dfC142f5F,
        0x43ef285F5e27D8CA978A7e577f4dDF52147EB77b,
        0x47cd6B7e7308Fb062586e5185B4F3Ee7E224eefe,
        0x9b6DB9Cc6E479dd28471B9C899890C20377DA200,
        0xFCfeD578958D42Cd1c2ea09db09bfC1A668E0efd,
        0x03572207d14bed3dd50E0d48CfaD44bDDB8BF4B7
    ];

    MultiValidatorFactory factory;
    MultiValidatorLST lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");

        vm.startBroadcast(privKey);
        address me = vm.addr(privKey);

        console2.log("Deploying MultiValidatorFactory...");
        address factoryImpl = address(new MultiValidatorFactory());
        factory =
            MultiValidatorFactory(address(new ERC1967Proxy{ salt: bytes32("MultiValidatorLSTFactory") }(address(factoryImpl), "")));
        factory.initialize();

        console2.log("MultiValidatorFactory deployed at: %s", address(factory));
        console2.log("Factory owner: %s", factory.owner());

        console2.log("Deploying MultiValidatorLST...");

        lst = MultiValidatorLST(factory.deploy(address(LPT)));

        console2.log("MultiValidatorLST deployed at: %s", address(lst));

        // deploy flash unstake wrapper
        address flashUnstake = address(new FlashUnstake());
        console2.log("FlashUnstake deployed at: %s", flashUnstake);

        lst.setFee(0.05e6); // 5% fee

        for (uint256 i = 0; i < tenderizers.length; i++) {
            lst.addValidator(payable(tenderizers[i]), 1_000_000 ether); // 2M Stake
        }

        vm.stopBroadcast();
    }
}
