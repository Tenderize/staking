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

import { Adapter } from "core/tenderize-v3/Adapter.sol";
import { IBittensor } from "core/tenderize-v3/bittensor/Bittensor.sol";

import { IERC165 } from "core/interfaces/IERC165.sol";

address constant STAKING_ADDRESS = 0x0000000000000000000000000000000000000801;

uint256 constant UNSTAKE_TIME = 50_400; // blocks
uint256 constant SUBNET_ID = 0; // Subnet zero

contract TaoAdapter is Adapter {
    error UnlockPending();

    struct Storage {
        uint256 lastUnlockID;
        mapping(uint256 => Unlock) unlocks;
    }

    struct Unlock {
        uint256 amount;
        uint256 startBlock;
    }

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.bittensor.adapter.storage.location")) - 1;

    function symbol() external pure returns (string memory) {
        return "TAO";
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
        Storage storage $ = _loadStorage();
        // TODO: Implement previewWithdraw
        return $.unlocks[unlockID].amount;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        Storage storage $ = _loadStorage();
        return $.unlocks[unlockID].startBlock + UNSTAKE_TIME;
    }

    function unlockTime() external pure override returns (uint256) {
        return UNSTAKE_TIME;
    }

    function currentTime() external view override returns (uint256) {
        return block.number;
    }

    function stake(bytes32 validator, uint256 /*amount*/ ) external override returns (uint256 staked) {
        IBittensor(STAKING_ADDRESS).addStake(validator, SUBNET_ID);
    }

    function unstake(bytes32 validator, uint256 amount) external override returns (uint256 unlockID) {
        IBittensor(STAKING_ADDRESS).removeStake(validator, amount, SUBNET_ID);
        Storage storage $ = _loadStorage();
        uint256 id = ++$.lastUnlockID;
        $.unlocks[id] = Unlock(amount, block.number);
    }

    function withdraw(bytes32, /*validator*/ uint256 unlockID) external override returns (uint256 amount) {
        Storage storage $ = _loadStorage();
        Unlock memory unlock = $.unlocks[unlockID];
        if (block.number < unlock.startBlock + UNSTAKE_TIME) {
            revert UnlockPending();
        }
        amount = unlock.amount;
        delete $.unlocks[unlockID];
    }

    function rebase(bytes32 validator, uint256 currentStake) external override returns (uint256 newStake) {
        bytes32 coldKey = H160toSS58(address(this));
        newStake = IBittensor(STAKING_ADDRESS).getStake(validator, coldKey, SUBNET_ID);
    }

    function isValidator(bytes32 validator) external view override returns (bool) {
        return true;
    }

    function H160toSS58(address ethAddr) public pure returns (bytes32 coldKey) {
        bytes memory input = abi.encodePacked("evm:", ethAddr);
    }
}
