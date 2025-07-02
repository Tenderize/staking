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

pragma solidity ^0.8.25;

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { MultiValidatorLST } from "core/tenderize-v3/multi-validator/MultiValidatorLST.sol";
import { UnstakeNFT } from "core/tenderize-v3/multi-validator/UnstakeNFT.sol";
import { Registry } from "core/registry/Registry.sol";

contract MultiValidatorFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    Registry immutable registry;
    address private immutable initialImpl;
    address private immutable initialUnstakeNFTImpl;

    event MultiValidatorLSTDeployed(string indexed tokenSymbol, address multiValidatorLST, address unstakeNFT);

    error ZeroAddress();
    error EmptySymbol();

    constructor(Registry _registry) {
        _disableInitializers();
        registry = _registry;
        initialImpl = address(new MultiValidatorLST{ salt: bytes32(uint256(0)) }(_registry));
        initialUnstakeNFTImpl = address(new UnstakeNFT{ salt: bytes32(uint256(0)) }());
    }

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        transferOwnership(registry.treasury());
    }

    /**
     * @notice Deploy a new MultiValidatorLST for a native token
     * @param tokenSymbol Symbol of the native token (e.g., "ETH", "SEI")
     * @return multiValidatorLST Address of the deployed MultiValidatorLST proxy
     */
    function deploy(string memory tokenSymbol) external onlyOwner returns (address multiValidatorLST) {
        if (bytes(tokenSymbol).length == 0) revert EmptySymbol();

        // Deploy MultiValidatorLST proxy
        multiValidatorLST =
            address(new ERC1967Proxy{ salt: keccak256(bytes(string.concat("MultiValidator", tokenSymbol))) }(initialImpl, ""));

        // Deploy UnstakeNFT proxy
        address unstakeNFTProxy = address(
            new ERC1967Proxy{ salt: keccak256(bytes(string.concat("UnstakeNFT", tokenSymbol))) }(
                initialUnstakeNFTImpl, abi.encodeCall(UnstakeNFT.initialize, (tokenSymbol, multiValidatorLST))
            )
        );

        // Initialize MultiValidatorLST
        MultiValidatorLST(payable(multiValidatorLST)).initialize(tokenSymbol, UnstakeNFT(unstakeNFTProxy), registry.treasury());

        // Transfer ownership of UnstakeNFT to registry treasury
        UnstakeNFT(unstakeNFTProxy).transferOwnership(registry.treasury());

        emit MultiValidatorLSTDeployed(tokenSymbol, multiValidatorLST, unstakeNFTProxy);
    }

    /**
     * @notice Get the predicted address for a MultiValidatorLST deployment
     * @param tokenSymbol Symbol of the native token
     * @return Predicted address of the MultiValidatorLST proxy
     */
    function getMultiValidatorLSTAddress(string memory tokenSymbol) external view returns (address) {
        bytes32 salt = keccak256(bytes(string.concat("MultiValidator", tokenSymbol)));
        bytes memory bytecode = abi.encodePacked(type(ERC1967Proxy).creationCode, abi.encode(initialImpl, ""));

        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))))));
    }

    /**
     * @notice Get the predicted address for an UnstakeNFT deployment
     * @param tokenSymbol Symbol of the native token
     * @param multiValidatorLST Address of the corresponding MultiValidatorLST
     * @return Predicted address of the UnstakeNFT proxy
     */
    function getUnstakeNFTAddress(string memory tokenSymbol, address multiValidatorLST) external view returns (address) {
        bytes32 salt = keccak256(bytes(string.concat("UnstakeNFT", tokenSymbol)));
        bytes memory bytecode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(initialUnstakeNFTImpl, abi.encodeCall(UnstakeNFT.initialize, (tokenSymbol, multiValidatorLST)))
        );

        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(bytecode))))));
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
