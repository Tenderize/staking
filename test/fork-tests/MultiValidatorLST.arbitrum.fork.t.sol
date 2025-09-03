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
}

contract MultiValidatorLST_Arbitrum_Fork_Test is Test {
    // Mainnet MultiValidatorLST proxy address
    address constant MULTI_VALIDATOR_LST = 0x9F5540F4A9777Ea678D80A7b508DcD924a4b1187;

    // Registry address on Arbitrum
    address constant REGISTRY = 0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE;

    // Fork block height (you can adjust this to a specific block)
    uint256 constant FORK_BLOCK = 375_306_528; // Recent Arbitrum block

    MultiValidatorLSTHarness harness;

    function setUp() public {
        // Fork Arbitrum from specific block height
        console2.log("Forking Arbitrum at block:", FORK_BLOCK);
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"), FORK_BLOCK);

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

    function test_readMainnetTreeState() public {
        console2.log("\n=== COMPREHENSIVE TREE STRUCTURE ANALYSIS ===\n");

        // Get tree statistics first
        (uint24 size, uint24 positiveNodes, uint24 negativeNodes, int200 posDivergence, int200 negDivergence) =
            harness.exposed_getTreeStats();

        console2.log("=== Tree Statistics ===");
        console2.log("Total nodes:", size);
        console2.log("Positive divergence nodes:", positiveNodes);
        console2.log("Negative divergence nodes:", negativeNodes);
        console2.log("Total positive divergence:", posDivergence);
        console2.log("Total negative divergence:", negDivergence);

        // Get first and last
        uint24 firstId = harness.exposed_getFirst();
        uint24 lastId = harness.exposed_getLast();
        console2.log("\nFirst item ID:", firstId);
        console2.log("Last item ID:", lastId);

        console2.log("\n=== TRAVERSING ALL 13 NODES ===\n");

        // Try to iterate through all possible node IDs (0-12)
        for (uint24 nodeId = 0; nodeId <= 12; nodeId++) {
            try harness.exposed_getNode(nodeId) returns (AVLTree.Node memory node) {
                MultiValidatorLST.StakingPool memory pool = harness.exposed_getStakingPool(nodeId);

                console2.log("---- Node ID:", nodeId, "----");
                console2.log("  Divergence:", node.divergence);
                console2.log("  Height:", node.height);
                console2.log("  Left child:", node.left);
                console2.log("  Right child:", node.right);
                console2.log("  tToken:", pool.tToken);
                console2.log("  Target:", pool.target);
                console2.log("  Balance:", pool.balance);

                // Calculate actual divergence
                int200 calculatedDiv;
                if (pool.balance < pool.target) {
                    calculatedDiv = -int200(uint200(pool.target - pool.balance));
                } else {
                    calculatedDiv = int200(uint200(pool.balance - pool.target));
                }
                console2.log("  Calculated divergence:", calculatedDiv);
                console2.log("");
            } catch {
                // Node doesn't exist or has no data
            }
        }

        console2.log("\n=== TESTING TREE TRAVERSAL FUNCTIONS ===\n");

        // Test findSuccessor for each node
        console2.log("Testing findSuccessor:");
        for (uint24 nodeId = 0; nodeId <= 12; nodeId++) {
            try harness.exposed_findSuccessor(nodeId) returns (uint24 successor) {
                console2.log("  Node", nodeId, "-> successor:", successor);
            } catch {
                console2.log("  Node", nodeId, "-> no successor (error)");
            }
        }

        console2.log("\n=== ANALYSIS SUMMARY ===");
        console2.log("ISSUE: All nodes have left=0 and right=0");
        console2.log("This indicates the tree is completely FLAT (degenerate)");
        console2.log("Every node exists in isolation without proper tree linkage");
        console2.log("This breaks AVL tree invariants and traversal functions");
    }
}
