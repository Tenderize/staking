// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

// Current implementation deployed at: 0x9f6b328527b1a3007E63d4c30B44811bcCF42057

import { Script } from "forge-std/Script.sol";
import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { Registry } from "core/registry/Registry.sol";
import { console2 } from "forge-std/console2.sol";

contract MultiUpgrade is Script {
    Registry constant registry = Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE);

    function run() public {
        vm.startBroadcast();

        address lst = address(new MultiValidatorLST{ salt: bytes32(uint256(2)) }(registry));

        console2.log("Multi LST deployed at: %s", lst);
    }
}
