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
        vm.startBroadcast(privKey);
        address lst = 0x312d7CD23148DA9Baac94b43f4E8557fCcFe824F;
        LPT.approve(lst, type(uint256).max);
        MultiValidatorLST(lst).deposit(msg.sender, 10 ether);

        uint256 bal = MultiValidatorLST(lst).balanceOf(msg.sender);

        MultiValidatorLST(lst).approve(0x59b86cf4d8B566602a687Bd9A2979792e73316d9, type(uint256).max);
        (uint256 out, uint256 fee) = FlashUnstake(0x59b86cf4d8B566602a687Bd9A2979792e73316d9).flashUnstakeQuote(
            lst, 0x686962481543d543934903C3FE8bDe8c5dB9Bd97, 1 ether
        );
        console2.log("Quote out: %s", out);
        console2.log("fee: %s", fee);

        (out, fee) = FlashUnstake(0x59b86cf4d8B566602a687Bd9A2979792e73316d9).flashUnstake(
            lst, 0x686962481543d543934903C3FE8bDe8c5dB9Bd97, 1 ether, out - 1
        );
        console2.log("Successfully flash unstaked");
        vm.stopBroadcast();
    }
}
