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

/*
source env
forge script deploy/2_Adapter.s.sol --broadcast --rpc-url $GOERLI_RPC_URL --verify --sig "run(address,string,address)" <REGISTRY>
<NAME{Graph,Livepeer}> <LPT_TOKEN>
*/

pragma solidity 0.8.17;

import "forge-std/Script.sol";
import "forge-std/console2.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import "core/adapters/LivepeerAdapter.sol";
import "core/adapters/GraphAdapter.sol";
import "core/registry/Registry.sol";

contract DeployAdapter is Script {
    function run(Registry registry, string memory name, address asset) external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        address adapter;
        if (stringsEq(name, "Graph")) {
            adapter = address(new GraphAdapter());
        } else if (stringsEq(name, "Livepeer")) {
            adapter = address(new LivepeerAdapter());
        } else {
            revert("Invalid adapter name");
        }

        registry.registerAdapter(asset, adapter);
        vm.stopBroadcast();

        console2.log("Adapter deployed and registered: %s", adapter);
    }

    function stringsEq(string memory str1, string memory str2) public pure returns (bool) {
        return keccak256(abi.encodePacked(str1)) == keccak256(abi.encodePacked(str2));
    }
}
