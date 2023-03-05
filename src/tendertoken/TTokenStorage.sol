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

abstract contract TTokenStorage {
    uint256 private constant ERC20_SLOT = uint256(keccak256("xyz.tenderize.tToken.storage.location")) - 1;

    struct ERC20Data {
        uint256 _totalShares;
        uint256 _totalSupply;
        mapping(address => uint256) shares;
        mapping(address => mapping(address => uint256)) allowance;
        mapping(address => uint256) nonces;
    }

    function _loadERC20Slot() internal pure returns (ERC20Data storage s) {
        uint256 slot = ERC20_SLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }
}
