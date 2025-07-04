// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

// @title Create2Deployer
// @notice Simple factory contract that can deploy other contracts using the CREATE2 opcode.
// @dev Inspired by OpenZeppelin's Create2 library. Provides helper functions to deploy a contract
//      deterministically and compute the deployed address ahead of time.

import { Create2 } from "openzeppelin-contracts/utils/Create2.sol";

contract Create2Deployer {
    /// @notice Emitted when a new contract is deployed via `deploy`.
    /// @param addr Address of the contract that was deployed.
    /// @param salt Salt that was supplied for the CREATE2 deployment.
    event Deployed(address indexed addr, bytes32 indexed salt);

    /// @notice Deploy a contract using `CREATE2`.
    /// @param amount Wei to forward to the newly deployed contract.
    /// @param salt   Salt to use for the deterministic deployment.
    /// @param bytecode Creation bytecode of the contract to deploy (i.e. `type(ContractName).creationCode`).
    /// @return addr Address of the deployed contract.
    function deploy(uint256 amount, bytes32 salt, bytes memory bytecode) external payable returns (address addr) {
        addr = Create2.deploy(amount, salt, bytecode);
        emit Deployed(addr, salt);
    }

    /// @notice Compute the address of a contract that would be deployed with the given parameters.
    /// @param salt   Salt to use for CREATE2.
    /// @param bytecodeHash keccak256 hash of the creation bytecode.
    /// @return addr Predicted address where the contract will be deployed.
    function computeAddress(bytes32 salt, bytes32 bytecodeHash) external view returns (address addr) {
        addr = Create2.computeAddress(salt, bytecodeHash, address(this));
    }
}
