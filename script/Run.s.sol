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

pragma solidity 0.8.25;

import { Script, console2 } from "forge-std/Script.sol";

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { MultiValidatorFactory } from "core/multi-validator/Factory.sol";
import { FlashUnstake, TenderSwap } from "core/multi-validator/FlashUnstake.sol";
<<<<<<< HEAD
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
=======
import { Tenderizer } from "core/tenderize-v3/Tenderizer.sol";
>>>>>>> 890b534 (Sei testnet deployment)
import { LPT } from "core/adapters/LivepeerAdapter.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

import { SeiAdapter } from "core/tenderize-v3/Sei/SeiAdapter.sol";
import { ISeiStaking, Delegation } from "core/tenderize-v3/Sei/Sei.sol";

address constant TENDERIZER_1 = 0x4b7339E599a599DBd7829a8ECA0d233ED4F7eA09;
address constant TENDERIZER_2 = 0xFB32bF22B4F004a088c1E7d69e29492f5D7CD7E1;
address constant TENDERIZER_3 = 0x6DFd5Cee0Ed2ec24Fdc814Ad857902DE01c065d6;
address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

interface ADDR {
    function getSeiAddr(address addr) external view returns (string memory response);
    function getEvmAddr(string memory addr) external view returns (address response);
}

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    MultiValidatorFactory factory;
    // MultiValidatorLST lst;

    address constant ADDR_PRECOMPILE = 0x0000000000000000000000000000000000001004;
    address constant STAKING_PRECOMPILE = 0x0000000000000000000000000000000000001005;

    function run() public payable {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);
        // console2.logString(
        //     SeiAdapter(0x59726AcA54DB5bA44888992A88e71af1E2D2f09C).validatorBytes32ToString(
        //         0x2af815558b165be177531446f693fb7e7f3563e1000000000000000000000000
        //     )
        // );

        Delegation memory del = ISeiStaking(STAKING_PRECOMPILE).delegation(
            0x28D5bC07301472829bab14aC26CF74676e9FB1d3, "seivaloper19tup24vtzed7za6nz3r0dylm0eln2clpvhtawu"
        );
        console2.log("del", del.balance.amount);
        console2.log("del", del.balance.denom);
        console2.log("del", del.delegation.delegator_address);
        console2.log("del", del.delegation.shares);
        console2.log("del", del.delegation.decimals);
        console2.log("del", del.delegation.validator_address);
        // SeiAdapter adapter = SeiAdapter(0xc7324079ACD020c2585DD00bc734d1a799D675fd);
        // (ok, ret) = adapter.debugRawDelegation(0x2af815558b165be177531446f693fb7e7f3563e1000000000000000000000000);
        // console2.log("ok", ok);
        // console2.logBytes(ret);
        // address payable lst = payable(0x28D5bC07301472829bab14aC26CF74676e9FB1d3);
        // Tenderizer(lst).deposit{ value: 1 ether }(msg.sender);
        vm.stopBroadcast();
    }
}
