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

import { console2 } from "forge-std/Test.sol";

import { Adapter } from "core/tenderize-v3/Adapter.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";

import {
    DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS,
    DelegatorSummary,
    Hyperliquid,
    L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS
} from "core/tenderize-v3/Hyperliquid/Hyperliquid.sol";

contract HypeAdapter is Adapter {
    error DelegatorSummaryFailed(address user);

    struct Storage {
        uint256 a;
    }

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.hyperliquid.adapter.storage.location")) - 1;

    function symbol() external pure returns (string memory) {
        return "HYPE";
    }

    function _loadStorage() internal pure returns (Storage storage $) {
        uint256 slot = STORAGE;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function previewDeposit(bytes32, /*validator*/ uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
        return 0;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        return 0;
    }

    function unlockTime() external pure override returns (uint256) {
        return 0;
    }

    function stake(bytes32 validator, uint256 /*amount*/ ) external payable override returns (uint256 staked) {
        return 0;
    }

    function unstake(bytes32 validator, uint256 amount) external override returns (uint256 unlockID) {
        return 0;
    }

    function withdraw(bytes32, /*validator*/ uint256 unlockID) external override returns (uint256 amount) {
        return 0;
    }

    function rebase(bytes32 validator, uint256 currentStake) external payable override returns (uint256 newStake) {
        address delegator = address(bytes20(validator));
        console2.log("delegator %s", delegator);
        uint256 currentTime = currentTime();
        console2.log("currentTime %s", currentTime);
        bool success;
        bytes memory result;
        (success, result) = DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS.staticcall(abi.encode(delegator));
        console2.log("success %s", success);
        console2.log("result: ");
        console2.logBytes(result);
        // TODO: switch to if conditiional + revert error
        if (!success) {
            revert DelegatorSummaryFailed(delegator);
        }
        DelegatorSummary memory del = abi.decode(result, (DelegatorSummary));
        console2.log("delegated %s", del.delegated);
        return del.delegated;
    }

    function isValidator(bytes32 validator) external view override returns (bool) {
        return true;
    }

    function currentTime() public view override returns (uint256) {
        bool success;
        bytes memory result;
        (success, result) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        console2.log("currentTime success %s", success);
        console2.log("currentTime result: ");
        console2.logBytes(result);
        require(success, "L1BlockNumber precompile call failed");
        return uint256(abi.decode(result, (uint64)));
    }
}
