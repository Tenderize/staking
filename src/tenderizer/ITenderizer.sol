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

import { IERC20 } from "core/interfaces/IERC20.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";

/**
 * @title ITenderizer
 * @author Tenderize Labs Ltd
 * @notice This interface can be used by external sources to interfact with a Tenderizer.
 * @dev Contains only the necessary API
 */
interface ITenderizer is IERC20 {
    function deposit(address receiver, uint256 assets) external returns (uint256);
    function unlock(uint256 assets) external returns (uint256 unlockID);
    function withdraw(address receiver, uint256 unlockID) external returns (uint256 amount);
    function rebase() external;
    function previewDeposit(uint256 assets) external view returns (uint256);
    function previewWithdraw(uint256 unlockID) external view returns (uint256);
    function unlockMaturity(uint256 unlockID) external view returns (uint256);
}
