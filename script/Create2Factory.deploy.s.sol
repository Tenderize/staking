// SPDX-License-Identifier: MIT
//
// Simple script to deploy the `Create2Factory` on any EVM-compatible network (e.g. Sei testnet)
// and print the deployed address. Run with:
//   forge script script/Create2Factory.deploy.s.sol --broadcast --rpc-url <SEI_RPC> --private-key $PRIVATE_KEY
//
// Contracts are deployed normally (not via create2) because the factory itself is responsible for
// subsequent CREATE2 deployments.
//
// solhint-disable no-console

pragma solidity >=0.8.19;

import { Script, console2 } from "forge-std/Script.sol";

import { Create2Deployer } from "core/utils/Create2Deployer.sol";

contract Create2FactoryDeploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        Create2Deployer factory = new Create2Deployer();
        console2.log("Create2Deployer deployed at:", address(factory));

        vm.stopBroadcast();
    }
}
