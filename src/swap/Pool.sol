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

import { ERC1155 } from "solmate/tokens/ERC1155.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { wadPow } from "solmate/utils/SignedWadMath.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";
import { SD59x18, sd, pow, fromSD59x18, E, wrap, unwrap } from "prb-math/SD59x18.sol";
import { Router } from "core/router/Router.sol";

import { LPToken } from "core/swap/LpToken.sol";

import { console } from "forge-std/Test.sol";

pragma solidity 0.8.17;

struct Pool {
    LPToken lpToken;
    uint256 assets;
    uint256 liabilities;
}

contract Metapool {
    error InvalidAsset(address asset);
    error InsufficientAssets(uint256 requested, uint256 available);
    error SlippageThresholdExceeded(uint256 out, uint256 minOut);

    event Deposit(address indexed asset, address indexed from, uint256 amount, uint256 lpSharesMinted);
    event Withdraw(address indexed asset, address indexed to, uint256 amount, uint256 lpSharesBurnt);
    event Swap(address indexed asset, address indexed caller, address toAsset, uint256 inAmount, uint256 outAmount);

    address private immutable LP_TOKEN_IMPLEMENTATION;
    address private immutable ROUTER;
    int256 private constant E_N = 2_718_281_828_459;
    int256 private constant E_D = 10e9;

    using ClonesWithImmutableArgs for address;

    using SafeTransferLib for ERC20;

    address public underlying;
    uint256 public totalAssets;
    uint256 public totalLiabilities;
    mapping(address => Pool) pools;

    constructor(address _underlying, address _lpToken, address _router) {
        underlying = _underlying;
        LP_TOKEN_IMPLEMENTATION = _lpToken;
        ROUTER = _router;
    }

    function getPool(address asset) public view returns (Pool memory) {
        return pools[asset];
    }

    function _createPool(address asset) internal {
        // TODO: check tenderizer underlying is the same as this pool's underlying
        if (asset != underlying && !Router(ROUTER).isTenderizer(asset)) {
            revert InvalidAsset(asset);
        }

        pools[asset] = Pool({
            lpToken: LPToken(LP_TOKEN_IMPLEMENTATION.clone(abi.encodePacked(asset, address(this)))),
            assets: 0,
            liabilities: 0
        });
    }

    function deposit(address asset, uint256 amount) public {
        Pool storage pool = pools[asset];

        if (address(pool.lpToken) == address(0)) {
            _createPool(asset);
        }

        uint256 lpShares = pool.liabilities == 0 ? amount : amount * pool.lpToken.totalSupply() / pool.liabilities;

        pool.assets += amount;
        pool.liabilities += amount;

        totalAssets += amount;
        totalLiabilities += amount;

        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        pool.lpToken.mint(msg.sender, lpShares);

        emit Deposit(asset, msg.sender, amount, lpShares);
    }

    function withdraw(address asset, uint256 amount) public {
        Pool storage pool = pools[asset];

        if (pool.assets < amount) {
            revert InsufficientAssets(amount, pool.assets);
        }

        uint256 lpShares = amount * pool.lpToken.totalSupply() / pool.liabilities;

        pool.assets -= amount;
        pool.liabilities -= amount;

        totalAssets -= amount;
        totalLiabilities -= amount;

        pool.lpToken.burn(msg.sender, lpShares);

        ERC20(asset).safeTransfer(msg.sender, amount);

        emit Withdraw(asset, msg.sender, amount, lpShares);
    }

    function withdrawOther(address asset, address otherAsset, uint256 amount) external returns (uint256 out) {
        Pool storage pool = pools[asset];
        Pool storage poolOther = pools[otherAsset];

        if (_score(pool.assets, pool.liabilities) >= 0) revert();

        if (poolOther.assets - poolOther.liabilities < amount) {
            revert InsufficientAssets(amount, poolOther.assets - poolOther.liabilities);
        }

        int256 s =
            _slippage(_score(poolOther.assets, poolOther.liabilities), _score(poolOther.assets - amount, poolOther.liabilities));

        out = amount * uint256(E_D - s) / uint256(E_D);
        uint256 lpShares = amount * pool.lpToken.totalSupply() / pool.liabilities;

        pool.liabilities -= amount;
        poolOther.assets -= out;

        pool.lpToken.burn(msg.sender, lpShares);

        ERC20(otherAsset).safeTransfer(msg.sender, out);

        emit Withdraw(otherAsset, msg.sender, out, lpShares);
    }

    function swap(address from, address to, uint256 amount, uint256 minOut) external returns (uint256 out) {
        Pool storage i = pools[from];
        Pool storage j = pools[to];
        out = _quote(i, j, amount);
        if (out < minOut) revert SlippageThresholdExceeded(out, minOut);

        i.assets += amount;
        j.assets -= out;

        ERC20(from).safeTransferFrom(msg.sender, address(this), amount);
        ERC20(to).safeTransfer(msg.sender, out);

        emit Swap(from, msg.sender, to, amount, out);
    }

    function quote(address from, address to, uint256 amount) external view returns (uint256 out) {
        Pool storage i = pools[from];
        Pool storage j = pools[to];
        out = _quote(i, j, amount);
    }

    function _quote(Pool storage i, Pool storage j, uint256 amount) internal view returns (uint256 out) {
        int256 s_i = _slippage(_score(i.assets, i.liabilities), _score(i.assets + amount, i.liabilities));
        int256 s_j = _slippage(_score(j.assets, j.liabilities), _score(j.assets - amount, j.liabilities));

        out = amount * uint256((E_D - (s_i - s_j))) / uint256(E_D);
    }

    function _slippage(int256 r, int256 rY) internal view returns (int256) {
        int256 slip = _slippageForScore(r);
        int256 slipY = _slippageForScore(rY);

        return (slipY - slip) * E_D / (rY - r);
    }

    function _slippageForScore(int256 r) internal pure returns (int256) {
        return wadPow(E_N, r * -400) / 5;
    }

    function _score(uint256 assets, uint256 liabilities) internal pure returns (int256 score) {
        if (assets < liabilities) {
            score = -int256((liabilities - assets) * 10e9 / (assets + liabilities));
        } else {
            score = int256((assets - liabilities) * 10e9 / (assets + liabilities));
        }
    }
}
