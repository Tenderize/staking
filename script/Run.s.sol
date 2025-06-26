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

pragma solidity 0.8.20;

import { Script, console2 } from "forge-std/Script.sol";

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { MultiValidatorFactory } from "core/multi-validator/Factory.sol";
import { FlashUnstake, TenderSwap } from "core/multi-validator/FlashUnstake.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { LPT } from "core/adapters/LivepeerAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

address constant TENDERIZER_1 = 0x4b7339E599a599DBd7829a8ECA0d233ED4F7eA09;
address constant TENDERIZER_2 = 0xFB32bF22B4F004a088c1E7d69e29492f5D7CD7E1;
address constant TENDERIZER_3 = 0x6DFd5Cee0Ed2ec24Fdc814Ad857902DE01c065d6;
address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    MultiValidatorFactory factory;
    // MultiValidatorLST lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        address guy = 0xF77fc3ae854164EAd1eeb39458d830Cd464270eD;
        address lst = 0xeab62Fb116f2e1f766A8a64094389553a00C2F68;
        vm.startBroadcast(guy);

        Tenderizer(payable(lst)).withdraw(guy, 64);

        vm.stopBroadcast();
    }
}
