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
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";
import { SD59x18, sd, pow, div, fromSD59x18, E, wrap, unwrap, lte, gte } from "prb-math/SD59x18.sol";

import { Router } from "core/router/Router.sol";
import { LPToken } from "core/swap/LpToken.sol";

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

    int256 private constant K = 0.005e18;
    int256 private constant N = 10e18;

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

        if (unwrap(_score(pool.assets, pool.liabilities)) >= 0) revert();

        if (poolOther.assets - poolOther.liabilities < amount) {
            revert InsufficientAssets(amount, poolOther.assets - poolOther.liabilities);
        }

        SD59x18 s =
            _slippage(_score(poolOther.assets, poolOther.liabilities), _score(poolOther.assets - amount, poolOther.liabilities));

        s = wrap(1e18).sub(s);

        out = amount * uint256(unwrap(s)) / 1e18;
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
        Pool memory i = pools[from];
        Pool memory j = pools[to];
        out = _quote(i, j, amount);
    }

    function score(address asset) external view returns (SD59x18) {
        Pool memory pool = pools[asset];
        return _score(pool.assets, pool.liabilities);
    }

    function _quote(Pool memory i, Pool memory j, uint256 amount) internal pure returns (uint256 out) {
        SD59x18 s_i = _slippage(_score(i.assets, i.liabilities), _score(i.assets + amount, i.liabilities));
        SD59x18 s_j = _slippage(_score(j.assets, j.liabilities), _score(j.assets - amount, j.liabilities));

        SD59x18 s = wrap(1e18).sub((s_i).sub(s_j));

        out = amount * uint256(unwrap(s)) / 1e18;
    }

    function _slippage(SD59x18 r, SD59x18 rY) internal pure returns (SD59x18) {
        SD59x18 slip = _slippageForScore(r);
        SD59x18 slipY = _slippageForScore(rY);

        return (slipY.sub(slip)).div(rY.sub(r));
    }

    function _slippageForScore(SD59x18 r) internal pure returns (SD59x18) {
        // slippage for a score `r`is defined as
        // `k / e^(r*n)`
        // where `k` is a constant and can be seen as the slippage at score 0
        // and `n`is the amplifier of the slippage function, lower `n` means a flatter curve
        if (r.lte(wrap(-0.5e18))) return wrap(1e18);
        return wrap(K).div(E.pow(r.mul(wrap(N))));
    }

    function _score(uint256 assets, uint256 liabilities) internal pure returns (SD59x18 r) {
        if (assets < liabilities) {
            r = wrap(-int256((liabilities - assets) * 1e18 / (assets + liabilities)));
        } else {
            r = wrap(int256((assets - liabilities) * 1e18 / (assets + liabilities)));
        }
    }
}
