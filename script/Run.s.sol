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

import { LPT } from "core/adapters/LivepeerAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

address constant TENDERIZER_1 = 0xFCfeD578958D42Cd1c2ea09db09bfC1A668E0efd;
address constant TENDERIZER_2 = 0x4b0e5E54Df6d5eCcC7B2F838982411DC93253dAf;
address constant TENDERIZER_3 = 0x218337076c79A6D94EB3B557f2c89dDd82E883A0;

address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    MultiValidatorFactory factory;
    // MultiValidatorLST lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        address lst = 0xfdc1E7Ec8dBab6D05f2655E0409a79550eCb01aE;
        LPT.approve(lst, type(uint256).max);
        MultiValidatorLST(lst).deposit(msg.sender, 10 ether);

        uint256 bal = MultiValidatorLST(lst).balanceOf(msg.sender);

        MultiValidatorLST(lst).approve(0x0Dbce9D1E875772cf370f14f10Cd22f71B6B6F95, type(uint256).max);
        (uint256 out, uint256 fee) = FlashUnstake(0x0Dbce9D1E875772cf370f14f10Cd22f71B6B6F95).flashUnstakeQuote(
            lst, 0x686962481543d543934903C3FE8bDe8c5dB9Bd97, 1 ether
        );
        console2.log("Quote out: %s", out);
        console2.log("fee: %s", fee);

        (out, fee) = FlashUnstake(0x0Dbce9D1E875772cf370f14f10Cd22f71B6B6F95).flashUnstake(
            lst, 0x686962481543d543934903C3FE8bDe8c5dB9Bd97, 1 ether, out - 1
        );
        console2.log("Successfully flash unstaked");
        vm.stopBroadcast();
    }
}
