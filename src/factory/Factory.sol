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

pragma solidity 0.8.17;

import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

import { Adapter } from "core/adapters/Adapter.sol";
import { Registry } from "core/registry/Registry.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";

/**
 * @title Factory
 * @author Tenderize Labs Ltd
 * @notice Factory for Tenderizer contracts
 */

contract Factory {
    using ClonesWithImmutableArgs for address;

    error InvalidAsset(address asset);
    error NotValidator(address validator);

    address public immutable registry;
    address public immutable tenderizerImpl;

    constructor(address _registry) {
        registry = _registry;
        tenderizerImpl = Registry(_registry).tenderizer();
    }

    /**
     * @notice Creates a new Tenderizer
     * @param asset Address of the underlying asset
     * @param validator Address of the validator
     * @return tenderizer Address of the created Tenderizer
     */
    function newTenderizer(address asset, address validator) external returns (address tenderizer) {
        Adapter adapter = Adapter(Registry(registry).adapter(asset));

        if (address(adapter) == address(0)) revert InvalidAsset(asset);
        if (!adapter.isValidator(validator)) revert NotValidator(validator);

        tenderizer = address(tenderizerImpl).clone(abi.encodePacked(asset, validator));

        // Reverts if caller is not a registered factory
        Registry(registry).registerTenderizer(asset, validator, tenderizer);
    }
}
