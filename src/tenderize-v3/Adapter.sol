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

import { IERC165 } from "core/interfaces/IERC165.sol";

pragma solidity ^0.8.25;

interface Adapter is IERC165 {
    function previewDeposit(bytes32 validator, uint256 assets) external view returns (uint256);

    function previewWithdraw(uint256 unlockID) external view returns (uint256);

    function unlockMaturity(uint256 unlockID) external view returns (uint256);

    function unlockTime() external view returns (uint256);

    function currentTime() external view returns (uint256);

    function stake(bytes32 validator, uint256 amount) external returns (uint256 staked);

    function unstake(bytes32 validator, uint256 amount) external returns (uint256 unlockID);

    function withdraw(bytes32 validator, uint256 unlockID) external returns (uint256 amount);

    function rebase(bytes32 validator, uint256 currentStake) external returns (uint256 newStake);

    function isValidator(bytes32 validator) external view returns (bool);

    function symbol() external view returns (string memory);
}

library AdapterDelegateCall {
    error AdapterDelegateCallFailed(string msg);

    function _delegatecall(Adapter adapter, bytes memory data) internal returns (bytes memory) {
        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returnData) = address(adapter).delegatecall(data);

        if (!success) {
            // Next 5 lines from https://ethereum.stackexchange.com/a/83577
            if (returnData.length < 68) revert AdapterDelegateCallFailed("");
            assembly {
                returnData := add(returnData, 0x04)
            }
            revert AdapterDelegateCallFailed(abi.decode(returnData, (string)));
        }

        return returnData;
    }
}
