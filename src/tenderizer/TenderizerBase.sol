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

import { Clone } from "clones/Clone.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";

/// @title TenderizerImmutableArgs
/// @notice Immutable arguments for Tenderizer
/// @dev Immutable arguments are appended to the proxy bytecode at deployment of a clone.
/// Arguments are appended to calldata when the proxy delegatecals to its implementation,
/// where these arguments can be read given their memory offset and length.
abstract contract TenderizerImmutableArgs is Clone {
    function asset() public pure returns (address) {
        return _getArgAddress(0); // start: 0 end: 19
    }

    function validator() public pure returns (address) {
        return _getArgAddress(20); // start: 20 end: 39
    }

    function _registry() internal pure returns (address) {
        return _getArgAddress(40); // start: 40 end: 59
    }

    function _unlocks() internal pure returns (Unlocks) {
        return Unlocks(_getArgAddress(60)); // start: 60 end: 79
    }
}

/// @title TenderizerEvents
/// @notice Events for Tenderizer
abstract contract TenderizerEvents {
    event Deposit(address indexed sender, address indexed receiver, uint256 assetsIn, uint256 tTokenOut);

    event Rebase(uint256 oldStake, uint256 newStake);

    event Unlock(address indexed receiver, uint256 assets, uint256 unlockID);

    event Withdraw(address indexed receiver, uint256 assets, uint256 unlockID);
}
