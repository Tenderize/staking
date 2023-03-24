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
import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";
import { SD59x18, sd, pow, div, fromSD59x18, E, wrap, unwrap, lte, gte, uUNIT, UNIT } from "prb-math/SD59x18.sol";

import { Router } from "core/router/Router.sol";
import { LPToken } from "core/swap/LpToken.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Multicall } from "core/utils/Multicall.sol";
import { SelfPermit } from "core/utils/SelfPermit.sol";

pragma solidity 0.8.17;

struct Pool {
    uint128 assets;
    uint128 liabilities;
    LPToken lpToken;
}

contract Metapool is Multicall, SelfPermit {
    using ClonesWithImmutableArgs for address;
    using SafeTransferLib for ERC20;
    using SafeCastLib for uint256;

    error InvalidAsset(address asset);
    error WrongMetapool(address actualUnderlying, address expectedUnderlying);
    error InsufficientAssets(uint256 requested, uint256 available);
    error SlippageThresholdExceeded(uint256 out, uint256 minOut);

    event Deposit(address indexed asset, address indexed from, uint128 amount, uint256 lpSharesMinted);
    event Withdraw(address indexed asset, address indexed to, uint128 amount, uint256 lpSharesBurnt);
    event Swap(address indexed asset, address indexed caller, address toAsset, uint256 inAmount, uint128 outAmount);

    // TODO: Convert to immutable args
    address private immutable UNDERLYING;
    address private immutable LP_TOKEN_IMPLEMENTATION;
    address private immutable ROUTER;

    // Fee parameters
    uint128 private constant FEE = 0.003e18;
    uint128 private constant FEE_DENOMINATOR = 1e18;

    // Slippage paramaters
    // `k` is the slippage at a score of 0
    // `n` is the steepness of the slippage curve
    SD59x18 private constant K = SD59x18.wrap(0.005e18);
    SD59x18 private constant N = SD59x18.wrap(10e18);

    // TODO: Convert to EIP-1967 structured storage
    uint256 public totalAssets;
    uint256 public totalLiabilities;
    mapping(address => Pool) pools;

    constructor(address _underlying, address _lpToken, address _router) {
        UNDERLYING = _underlying;
        LP_TOKEN_IMPLEMENTATION = _lpToken;
        ROUTER = _router;
    }

    function getPool(address asset) public view returns (Pool memory) {
        return pools[asset];
    }

    function deposit(address asset, uint128 amount) public {
        Pool memory pool = pools[asset];

        _checkRebase(asset, pool);

        // Create pool if it doesn't exist
        if (address(pool.lpToken) == address(0)) {
            pool = _createPool(asset);
        }

        // Calculate LP shares to mint
        uint256 lpShares = pool.liabilities == 0 ? amount : amount * pool.lpToken.totalSupply() / pool.liabilities;

        // Update pool state
        pool.assets += amount;
        pool.liabilities += amount;

        // Update metapool state
        totalAssets += amount;
        totalLiabilities += amount;

        // Transfer tokens to pool
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint LP shares to depositor
        pool.lpToken.mint(msg.sender, lpShares);

        pools[asset] = pool;

        emit Deposit(asset, msg.sender, amount, lpShares);
    }

    function withdraw(address asset, uint128 amount) public {
        Pool memory pool = pools[asset];

        _checkRebase(asset, pool);

        // Revert if pool has insufficient assets
        if (pool.assets < amount) {
            revert InsufficientAssets(amount, pool.assets);
        }

        // Calculate LP shares to burn
        uint256 lpShares = amount * pool.lpToken.totalSupply() / pool.liabilities;

        // Update pool state
        pool.assets -= amount;
        pool.liabilities -= amount;

        // Update metapool state
        totalAssets -= amount;
        totalLiabilities -= amount;

        // Burn LP shares from depositor
        pool.lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to depositor
        ERC20(asset).safeTransfer(msg.sender, amount);

        pools[asset] = pool;

        emit Withdraw(asset, msg.sender, amount, lpShares);
    }

    function withdrawOther(address asset, address otherAsset, uint128 amount) external returns (uint128 out) {
        Pool memory pool = pools[asset];
        Pool memory otherPool = pools[otherAsset];

        _checkRebase(asset, pool);
        _checkRebase(otherAsset, otherPool);

        // Can only withdrawOther if `asset` has a score less than 0
        if (unwrap(_score(pool.assets, pool.liabilities)) >= 0) revert();

        // Withdrawing from `otherAsset` can't reduce its score below 0
        if (otherPool.assets - otherPool.liabilities < amount) {
            revert InsufficientAssets(amount, otherPool.assets - otherPool.liabilities);
        }

        // Calculate slippage for reducing score from `otherAsset`
        SD59x18 s =
            _slippage(_score(otherPool.assets, otherPool.liabilities), _score(otherPool.assets - amount, otherPool.liabilities));

        s = wrap(1e18).sub(s);

        out = (amount * uint256(unwrap(s)) / 1e18).safeCastTo128();

        // Calculate LP shares to burn from depositer for `asset`
        uint256 lpShares = amount * pool.lpToken.totalSupply() / pool.liabilities;

        // update liabilities for `asset`
        pool.liabilities -= amount;
        // update assets for `otherAsset`
        otherPool.assets -= uint128(out);

        // Burn LP shares from depositor for `asset`
        pool.lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to depositor for `otherAsset`
        ERC20(otherAsset).safeTransfer(msg.sender, out);

        pools[asset] = pool;
        pools[otherAsset] = otherPool;

        emit Withdraw(otherAsset, msg.sender, out, lpShares);
    }

    function swap(address from, address to, uint128 amount, uint128 minOut) external returns (uint128 out) {
        Pool memory i = pools[from];
        Pool memory j = pools[to];

        _checkRebase(from, i);
        _checkRebase(to, j);

        // calculate fee
        uint128 fee = amount * FEE / FEE_DENOMINATOR;

        // quote output amount for `amount` of `from` to `to`
        out = _quote(i, j, amount - fee);

        // Revert if slippage threshold is exceeded, i.e. if `out` is less than `minOut`
        if (out < minOut) revert SlippageThresholdExceeded(out, minOut);

        // Add `amount` to `from` pool assets
        i.assets += amount;
        //  Add `fee` to `from` pool liabilities
        i.liabilities += fee;
        // Subtract `out` from `to` pool assets
        j.assets -= out;

        // Transfer `amount` of `from` to this pool
        ERC20(from).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer `out` of `to` to msg.sender
        ERC20(to).safeTransfer(msg.sender, out);

        pools[from] = i;
        pools[to] = j;

        emit Swap(from, msg.sender, to, amount, out);
    }

    function quote(address from, address to, uint256 amount) external view returns (uint128 out) {
        // Use a memory cache to save gas
        Pool memory i = pools[from];
        Pool memory j = pools[to];
        out = _quote(i, j, amount);
    }

    function score(address asset) external view returns (SD59x18) {
        Pool memory pool = pools[asset];
        return _score(pool.assets, pool.liabilities);
    }

    function _quote(Pool memory i, Pool memory j, uint256 amount) internal pure returns (uint128 out) {
        // Get the slippage for increasing the score of pool `i`
        SD59x18 s_i = _slippage(_score(i.assets, i.liabilities), _score(i.assets + amount, i.liabilities));
        // Get the slippage for decreasing the score of pool `j`
        SD59x18 s_j = _slippage(_score(j.assets, j.liabilities), _score(j.assets - amount, j.liabilities));

        // Calculate the multiplier as `1 - slippage`
        SD59x18 s = UNIT.sub((s_i).sub(s_j));

        // Calculate the output amount as `amount * (1 - slippage)` and safecast to uint128
        out = (amount * uint256(unwrap(s)) / 1e18).safeCastTo128();
    }

    function _slippage(SD59x18 r, SD59x18 rY) internal pure returns (SD59x18) {
        SD59x18 slip = _slippageForScore(r);
        SD59x18 slipY = _slippageForScore(rY);

        // The slippage for changing the score from `r` to `rY` is defined as
        // `(slipY - slip) / (rY - r)`
        return (slipY.sub(slip)).div(rY.sub(r));
    }

    function _slippageForScore(SD59x18 r) internal pure returns (SD59x18) {
        // slippage for a score `r`is defined as
        // `k / e^(r*n)`
        // where `k` is a constant and can be seen as the slippage at score 0
        // and `n`is the amplifier of the slippage function, lower `n` means a flatter curve

        // If `r` is less than -0.5 return 100% slippage
        if (r.lte(wrap(-0.5e18))) return UNIT;
        return K.div(E.pow(r.mul(N)));
    }

    function _score(uint256 assets, uint256 liabilities) internal pure returns (SD59x18 r) {
        if (assets < liabilities) {
            r = wrap(-int256((liabilities - assets) * 1e18 / (assets + liabilities)));
        } else {
            r = wrap(int256((assets - liabilities) * 1e18 / (assets + liabilities)));
        }
    }

    function _checkRebase(address asset, Pool memory pool) internal view {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        if (balance == pool.assets) {
            return;
        } else if (balance > pool.assets) {
            uint128 diff = (balance - pool.assets).safeCastTo128();
            pool.assets = pool.assets + diff;
            pool.liabilities += diff;
        } else {
            uint128 diff = (pool.assets - balance).safeCastTo128();
            pool.assets < diff ? 0 : pool.assets - diff;
            pool.liabilities -= diff;
        }
    }

    function _createPool(address asset) internal returns (Pool memory pool) {
        // Check that `asset` is the UNDERLYING asset for the metapool or a tenderizer
        if (asset != UNDERLYING && !Router(ROUTER).isTenderizer(asset)) {
            revert InvalidAsset(asset);
        }

        // Check that tenderizer is for the same UNDERLYING asset as this Metapool
        {
            // Prevent a call to Tenderizer.asset() if `asset` is `underlying`
            address assetUnderlying;
            if (asset != UNDERLYING && (assetUnderlying = Tenderizer(asset).asset()) != UNDERLYING) {
                revert WrongMetapool(assetUnderlying, UNDERLYING);
            }
        }

        // Create an LP token for the new pool
        pool = Pool({
            lpToken: LPToken(LP_TOKEN_IMPLEMENTATION.clone(abi.encodePacked(asset, address(this)))),
            assets: 0,
            liabilities: 0
        });
    }
}
