// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { Test, console2 } from "forge-std/Test.sol";
import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { Registry } from "core/registry/Registry.sol";
import { AVLTree } from "core/multi-validator/AVLTree.sol";
import { UnstakeNFT } from "core/multi-validator/UnstakeNFT.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

// Test harness that exposes internal tree state for testing
contract MultiValidatorLSTHarness is MultiValidatorLST {
    using AVLTree for AVLTree.Tree;

    constructor(Registry _registry) MultiValidatorLST(_registry) { }

    // Expose tree read functions
    function exposed_getFirst() external view returns (uint24) {
        return stakingPoolTree.getFirst();
    }

    function exposed_getLast() external view returns (uint24) {
        return stakingPoolTree.getLast();
    }

    function exposed_getNode(uint24 id) external view returns (AVLTree.Node memory) {
        return stakingPoolTree.getNode(id);
    }

    function exposed_getTreeStats() external view returns (uint24, uint24, uint24, int200, int200) {
        return stakingPoolTree.getTreeStats();
    }

    function exposed_getStakingPool(uint24 id) external view returns (StakingPool memory) {
        return stakingPools[id];
    }

    function exposed_findSuccessor(uint24 id) external view returns (uint24) {
        return stakingPoolTree.findSuccessor(id);
    }

    function exposed_findPredecessor(uint24 id) external view returns (uint24) {
        return stakingPoolTree.findPredecessor(id);
    }
}

contract MultiValidatorLST_Arbitrum_Fork_Test is Test {
    // Mainnet MultiValidatorLST proxy address
    address constant MULTI_VALIDATOR_LST = 0x9F5540F4A9777Ea678D80A7b508DcD924a4b1187;

    // Registry address on Arbitrum
    address constant REGISTRY = 0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE;

    // Fork block height (you can adjust this to a specific block)
    uint256 constant FORK_BLOCK = 377_027_947; // Recent Arbitrum block

    MultiValidatorLSTHarness harness;
    address treasuryAddr;

    function setUp() public {
        // Fork Arbitrum from specific block height
        console2.log("Forking Arbitrum at block:", block.number);
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"));

        // Deploy the harness implementation
        console2.log("Deploying MultiValidatorLSTHarness...");
        harness = new MultiValidatorLSTHarness(Registry(REGISTRY));

        // Get the current MultiValidatorLST instance
        MultiValidatorLST currentLST = MultiValidatorLST(MULTI_VALIDATOR_LST);

        // We need UPGRADE_ROLE to perform the upgrade
        // First, let's check who has the UPGRADE_ROLE
        bytes32 UPGRADE_ROLE = keccak256("UPGRADE");

        // Get an account with UPGRADE_ROLE
        // In production, this would be the treasury or governance
        // For testing, we'll impersonate an account with this role

        // First check if treasury has the role
        address treasury = Registry(REGISTRY).treasury();
        treasuryAddr = treasury;
        console2.log("Treasury address:", treasury);

        // Impersonate the treasury to perform upgrade
        vm.startPrank(treasury);

        // Check if treasury has UPGRADE_ROLE
        bool hasTreasuryRole = currentLST.hasRole(UPGRADE_ROLE, treasury);

        if (!hasTreasuryRole) {
            // If treasury doesn't have the role, we need to find who does
            // For this test, we'll grant ourselves the role by impersonating someone who can
            console2.log("Treasury doesn't have UPGRADE_ROLE, attempting to get role...");

            // The UPGRADE_ROLE admin is UPGRADE_ROLE itself (self-administered)
            // We need to find an existing member
            // For testing purposes, let's try some common addresses

            // Try to upgrade anyway - in fork tests we can be more permissive
            vm.stopPrank();

            // Use vm.store to directly set storage if needed
            // Or find the actual upgrade role holder from events/logs

            // For simplicity in this test, let's directly upgrade using vm.prank
            // with a known upgrade role holder or bypass the check

            // Alternative approach: directly call upgrade as if we have the role
            vm.startPrank(MULTI_VALIDATOR_LST);
        }

        console2.log("Upgrading MultiValidatorLST to harness...");

        // Perform the upgrade
        try UUPSUpgradeable(MULTI_VALIDATOR_LST).upgradeTo(address(harness)) {
            console2.log("Upgrade successful!");
        } catch Error(string memory reason) {
            console2.log("Upgrade failed:", reason);
            // For testing, we can force the upgrade using vm.store if needed
            // This directly modifies the implementation slot
            bytes32 IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
            vm.store(MULTI_VALIDATOR_LST, IMPLEMENTATION_SLOT, bytes32(uint256(uint160(address(harness)))));
            console2.log("Forced upgrade via storage manipulation");
        }

        vm.stopPrank();

        // Cast the proxy to our harness
        harness = MultiValidatorLSTHarness(MULTI_VALIDATOR_LST);
    }

    function test_ReadMainnetTreeState() public {
        console2.log("\n========================================");
        console2.log("    AVL TREE STRUCTURE VISUALIZATION");
        console2.log("========================================\n");

        // Get tree statistics first
        (uint24 size, uint24 positiveNodes, uint24 negativeNodes, int200 posDivergence, int200 negDivergence) =
            harness.exposed_getTreeStats();

        console2.log("TREE SUMMARY:");
        console2.log("  Total Nodes:     ", size);
        console2.log("  Positive Nodes:  ", positiveNodes);
        console2.log("  Positive Divergence:  ", posDivergence);
        console2.log("  Negative Nodes:  ", negativeNodes);
        console2.log("  Negative Divergence:  ", negDivergence);
        console2.log("");

        // Build a mapping of all nodes first
        uint24[] memory nodeIds = new uint24[](13);
        uint256 validNodeCount = 0;

        for (uint24 i = 1; i <= 13; i++) {
            try harness.exposed_getNode(i) returns (AVLTree.Node memory) {
                nodeIds[validNodeCount] = i;
                validNodeCount++;
            } catch {
                // Node doesn't exist
            }
        }

        console2.log("========================================");
        console2.log("         IN-ORDER TRAVERSAL");
        console2.log("     (Left to Right by Divergence)");
        console2.log("========================================\n");

        // Traverse the tree in order (from smallest to largest divergence)
        uint24 currentId = harness.exposed_getFirst();
        uint256 position = 1;

        // Track visited nodes to prevent infinite loop
        uint256 maxIterations = validNodeCount + 1; // Safety limit
        uint256 iterations = 0;

        while (currentId != 0 && iterations < maxIterations) {
            AVLTree.Node memory node = harness.exposed_getNode(currentId);
            MultiValidatorLST.StakingPool memory pool = harness.exposed_getStakingPool(currentId);

            // console2.log(string(abi.encodePacked("[", _uint2str(position), "] Node ID: ", _uint2str(currentId))));
            // console2.log("    Balance:    ", pool.balance);
            // console2.log("    Target:     ", pool.target);
            // console2.log("    Divergence: ", node.divergence);

            // // Show over/under allocation - check actual balance vs target
            // if (pool.balance > pool.target) {
            //     console2.log("    Status:      OVER-ALLOCATED by", pool.balance - pool.target);
            // } else if (pool.balance < pool.target) {
            //     console2.log("    Status:      UNDER-ALLOCATED by", pool.target - pool.balance);
            // } else {
            //     console2.log("    Status:      PERFECTLY BALANCED");
            // }
            // console2.log("");

            uint24 nextId = harness.exposed_findSuccessor(currentId);

            // If successor is 0 or we're back to a node we've seen, we're done
            if (nextId == 0) {
                break;
            }

            currentId = nextId;
            position++;
            iterations++;
        }

        console2.log("========================================");
        console2.log("         TREE STRUCTURE");
        console2.log("    (Parent -> Children Relationships)");
        console2.log("========================================\n");

        // Find the root node (node with maximum height)
        uint24 rootId = 0;
        uint8 maxHeight = 0;

        for (uint256 i = 0; i < validNodeCount; i++) {
            AVLTree.Node memory node = harness.exposed_getNode(nodeIds[i]);
            if (node.height > maxHeight) {
                maxHeight = node.height;
                rootId = nodeIds[i];
            }
        }

        if (rootId != 0) {
            console2.log("ROOT NODE:", rootId);
            _printTreeStructure(rootId, 0, "");
        }

        console2.log("\n========================================");
        console2.log("         NODE DETAILS TABLE");
        console2.log("========================================\n");

        console2.log("ID  | Height | Left | Right | Balance         | Target          | Divergence");
        console2.log("----+--------+------+-------+-----------------+-----------------+-----------");

        for (uint256 i = 0; i < validNodeCount; i++) {
            uint24 nodeId = nodeIds[i];
            AVLTree.Node memory node = harness.exposed_getNode(nodeId);
            MultiValidatorLST.StakingPool memory pool = harness.exposed_getStakingPool(nodeId);

            console2.log(
                string(
                    abi.encodePacked(
                        _padRight(_uint2str(nodeId), 3),
                        " | ",
                        _padRight(_uint2str(node.height), 6),
                        " | ",
                        _padRight(_uint2str(node.left), 4),
                        " | ",
                        _padRight(_uint2str(node.right), 5),
                        " | ",
                        _padRight(_uint2str(pool.balance), 15),
                        " | ",
                        _padRight(_uint2str(pool.target), 15),
                        " | ",
                        _int2str(node.divergence)
                    )
                )
            );
        }

        console2.log("\n========================================\n");
    }

    function test_ClaimRewardsFork() public {
        // vm.startBroadcast();
        // // harness.claimValidatorRewards(9);
        // for (uint24 i = 1; i <= 13; i++) {
        //     harness.claimValidatorRewards(i);
        // }
        // vm.stopBroadcast();
        vm.prank(treasuryAddr);
        uint24[] memory ids = new uint24[](13);
        for (uint24 i = 0; i < 13; i++) {
            ids[i] = i + 1;
        }
        harness.migrate_RebuildTreeFromIds(ids);
        // vm.startBroadcast();
        for (uint24 i = 1; i < 13; i++) {
            test_ReadMainnetTreeState();
            harness.claimValidatorRewards(i);
        }
        // vm.stopBroadcast();
        test_ReadMainnetTreeState();
    }

    // Helper function to print tree structure recursively
    function _printTreeStructure(uint24 nodeId, uint256 depth, string memory prefix) private view {
        if (nodeId == 0) return;

        AVLTree.Node memory node = harness.exposed_getNode(nodeId);
        MultiValidatorLST.StakingPool memory pool = harness.exposed_getStakingPool(nodeId);

        // Create indentation
        string memory indent = "";
        for (uint256 i = 0; i < depth; i++) {
            indent = string(abi.encodePacked(indent, "  "));
        }

        // Print current node
        console2.log(
            string(
                abi.encodePacked(
                    indent,
                    prefix,
                    "Node ",
                    _uint2str(nodeId),
                    " [Bal: ",
                    _uint2str(pool.balance),
                    ", Div: ",
                    _int2str(node.divergence),
                    "]"
                )
            )
        );

        // Print children
        if (node.left != 0) {
            _printTreeStructure(node.left, depth + 1, "L-> ");
        }
        if (node.right != 0) {
            _printTreeStructure(node.right, depth + 1, "R-> ");
        }
    }

    // Helper function to convert uint to string
    function _uint2str(uint256 value) private pure returns (string memory) {
        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    // Helper function to convert int to string
    function _int2str(int200 value) private pure returns (string memory) {
        if (value >= 0) {
            return _uint2str(uint200(value));
        } else {
            return string(abi.encodePacked("-", _uint2str(uint200(-value))));
        }
    }

    // Helper function to pad string to the right
    function _padRight(string memory str, uint256 length) private pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        if (strBytes.length >= length) {
            return str;
        }
        bytes memory result = new bytes(length);
        uint256 i;
        for (i = 0; i < strBytes.length; i++) {
            result[i] = strBytes[i];
        }
        for (; i < length; i++) {
            result[i] = " ";
        }
        return string(result);
    }
}
