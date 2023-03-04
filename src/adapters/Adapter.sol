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

interface Adapter {
    function previewDeposit(uint256 assets) external view returns (uint256);

    function unlockMaturity(uint256 unlockID) external view returns (uint256);

    function previewWithdraw(uint256 unlockID) external view returns (uint256);

    function getTotalStaked(address validator) external view returns (uint256);

    function stake(address validator, uint256 amount) external;

    function unstake(address validator, uint256 amount) external returns (uint256 unlockID);

    function withdraw(address validator, uint256 unlockID) external;

    function claimRewards(address validator, uint256 currentStake) external returns (uint256 newStake);
}

library AdapterDelegateCall {
    error AdapterDelegateCallFailed(string msg);

    function _delegatecall(Adapter adapter, bytes memory data) internal returns (bytes memory) {
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
