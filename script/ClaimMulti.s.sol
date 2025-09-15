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
import { Tenderizer } from "core/tenderize-v3/Tenderizer.sol";
import { LPT } from "core/adapters/LivepeerAdapter.sol";
import { GRT } from "core/adapters/GraphAdapter.sol";
import { GraphAdapter } from "core/adapters/GraphAdapter.sol";
import { Registry } from "core/registry/Registry.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { FlashUnstake } from "core/multi-validator/FlashUnstake.sol";

import { SeiAdapter } from "core/tenderize-v3/Sei/SeiAdapter.sol";
import { ISeiStaking, Delegation } from "core/tenderize-v3/Sei/Sei.sol";

address constant TENDERIZER_1 = 0x4b7339E599a599DBd7829a8ECA0d233ED4F7eA09;
address constant TENDERIZER_2 = 0xFB32bF22B4F004a088c1E7d69e29492f5D7CD7E1;
address constant TENDERIZER_3 = 0x6DFd5Cee0Ed2ec24Fdc814Ad857902DE01c065d6;
address constant LIVEPEER_MINTER = 0xc20DE37170B45774e6CD3d2304017fc962f27252;

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";

contract MultiValidatorLST_Deploy is Script {
    bytes32 private constant salt = bytes32(uint256(1));

    MultiValidatorFactory factory;
    // MultiValidatorLST lst;

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        // address owner = 0xc1cFab553835D74717c4499793EEa6Ef198A3031;
        // vm.startBroadcast(owner);

        // Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE).registerAdapter(address(GRT), address(new GraphAdapter()));
        // vm.stopBroadcast();
        // address guy = 0x838afC2DE97D97A1ab478A8297292482A278A9CA;
        // address lst = 0x4003E23bE46f3Bf2B50c3c7F8B13aAeCDc71EA72;
        // vm.startBroadcast(guy);
        // // console2.log("unlock maturity", Tenderizer(payable(lst)).unlockMaturity(4));
        // Tenderizer(payable(lst)).withdraw(guy, 116);

        // vm.stopBroadcast();

        // livepeer 0x388b0faf9de300ffc21e3dc849202544901792cb
        // graph 0x9f5540f4a9777ea678d80a7b508dcd924a4b1187
        vm.startBroadcast(privKey);

        address lpt = 0x388B0fAf9DE300ffC21e3DC849202544901792CB;
        address grt = 0x9F5540F4A9777Ea678D80A7b508DcD924a4b1187;

        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(1);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(2);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(3);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(4);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(5);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(6);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(7);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(8);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(9);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(10);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(11);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(12);
        // MultiValidatorLST(payable(lpt)).claimValidatorRewards(13);

        for (uint24 i = 1; i <= 13; i++) {
            MultiValidatorLST(payable(grt)).claimValidatorRewards(i);
            MultiValidatorLST(payable(lpt)).claimValidatorRewards(i);
        }

        vm.stopBroadcast();
    }
}
