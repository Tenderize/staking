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
import { Clone } from "clones/Clone.sol";
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

contract MetapoolImmutableArgs is Clone {
    function underlying() public pure returns (address) {
        return _getArgAddress(0); // start: 0 end: 19
    }

    function _router() internal pure returns (address) {
        return _getArgAddress(20); // start: 20 end: 39
    }

    function _lpToken() internal pure returns (address) {
        return _getArgAddress(40); // start: 40 end: 59
    }
}

contract Metapool is MetapoolImmutableArgs, Multicall, SelfPermit {
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

    // Fee parameters
    uint128 private constant FEE = 0.003e18;
    uint128 private constant FEE_DENOMINATOR = 1e18;

    // Slippage paramaters
    // `k` is the slippage at a score of 0
    // `n` is the steepness of the slippage curve
    SD59x18 private constant K = SD59x18.wrap(0.005e18);
    SD59x18 private constant N = SD59x18.wrap(10e18);

    uint256 private constant SSLOT = uint256(keccak256("xyz.tenderize.swap.storage.location")) - 1;

    struct Data {
        uint128 totalAssets;
        uint128 totalLiabilities;
        mapping(address => Pool) pools;
    }

    function _loadStorageSlot() internal pure returns (Data storage s) {
        uint256 slot = SSLOT;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }

    function pool(address asset) external view returns (Pool memory) {
        Data storage s = _loadStorageSlot();

        return s.pools[asset];
    }

    function totalAssets() external view returns (uint128) {
        Data storage s = _loadStorageSlot();

        return s.totalAssets;
    }

    function totalLiabilities() external view returns (uint128) {
        Data storage s = _loadStorageSlot();

        return s.totalLiabilities;
    }

    function deposit(address asset, uint128 amount) external {
        Data storage s = _loadStorageSlot();

        Pool memory p = s.pools[asset];

        // Create pool if it doesn't exist
        if (address(p.lpToken) == address(0)) {
            p = _createPool(asset);
        }

        _checkRebase(asset, p);

        // Calculate LP shares to mint
        uint256 lpShares = p.liabilities == 0 ? amount : amount * p.lpToken.totalSupply() / p.liabilities;

        // Update pool state
        p.assets += amount;
        p.liabilities += amount;

        // Update metapool state
        s.totalAssets += amount;
        s.totalLiabilities += amount;

        // Transfer tokens to pool
        ERC20(asset).safeTransferFrom(msg.sender, address(this), amount);

        // Mint LP shares to depositor
        p.lpToken.mint(msg.sender, lpShares);

        s.pools[asset] = p;

        emit Deposit(asset, msg.sender, amount, lpShares);
    }

    function withdraw(address asset, uint128 amount) external {
        Data storage s = _loadStorageSlot();

        Pool memory p = s.pools[asset];

        _checkRebase(asset, p);

        // Revert if pool has insufficient assets
        if (p.assets < amount) {
            revert InsufficientAssets(amount, p.assets);
        }

        // Calculate LP shares to burn
        uint256 lpShares = amount * p.lpToken.totalSupply() / p.liabilities;

        // Update pool state
        p.assets -= amount;
        p.liabilities -= amount;

        // Update metapool state
        s.totalAssets -= amount;
        s.totalLiabilities -= amount;

        // Burn LP shares from depositor
        p.lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to depositor
        ERC20(asset).safeTransfer(msg.sender, amount);

        s.pools[asset] = p;

        emit Withdraw(asset, msg.sender, amount, lpShares);
    }

    function withdrawOther(address asset, address otherAsset, uint128 amount) external returns (uint128 out) {
        Data storage s = _loadStorageSlot();

        Pool memory p = s.pools[asset];
        Pool memory op = s.pools[otherAsset];

        _checkRebase(asset, p);
        _checkRebase(otherAsset, op);

        // Can only withdrawOther if `asset` has a score less than 0
        if (unwrap(_score(p.assets, p.liabilities)) >= 0) revert();

        // Withdrawing from `otherAsset` can't reduce its score below 0
        if (p.assets - p.liabilities < amount) {
            revert InsufficientAssets(amount, op.assets - op.liabilities);
        }

        // Calculate slippage for reducing score from `otherAsset`
        SD59x18 sl = _slippage(_score(op.assets, op.liabilities), _score(op.assets - amount, op.liabilities));

        sl = UNIT.sub(sl);

        out = (amount * uint256(unwrap(sl)) / 1e18).safeCastTo128();

        // Calculate LP shares to burn from depositer for `asset`
        uint256 lpShares = amount * p.lpToken.totalSupply() / p.liabilities;

        // update liabilities for `asset`
        p.liabilities -= amount;
        // update assets for `otherAsset`
        op.assets -= uint128(out);

        // Burn LP shares from depositor for `asset`
        p.lpToken.burn(msg.sender, lpShares);

        // Transfer tokens to depositor for `otherAsset`
        ERC20(otherAsset).safeTransfer(msg.sender, out);

        s.pools[asset] = p;
        s.pools[otherAsset] = op;

        emit Withdraw(otherAsset, msg.sender, out, lpShares);
    }

    function swap(address from, address to, uint128 amount, uint128 minOut) external returns (uint128 out) {
        Data storage s = _loadStorageSlot();

        Pool memory i = s.pools[from];
        Pool memory j = s.pools[to];

        _checkRebase(from, i);
        _checkRebase(to, j);

        // quote output amount for `amount` of `from` to `to`
        uint128 fee;
        (out, fee) = _quote(i, j, amount);

        // Revert if slippage threshold is exceeded, i.e. if `out` is less than `minOut`
        if (out < minOut) revert SlippageThresholdExceeded(out, minOut);

        // Add `amount` to `from` pool assets
        i.assets += amount;
        // Subtract `out` to `to` pool assets
        j.assets -= out;
        //  Add `fee` to `to` pool liabilities
        j.liabilities += fee;

        // Transfer `amount` of `from` to this pool
        ERC20(from).safeTransferFrom(msg.sender, address(this), amount);

        // Transfer `out` of `to` to msg.sender
        ERC20(to).safeTransfer(msg.sender, out);

        s.pools[from] = i;
        s.pools[to] = j;

        emit Swap(from, msg.sender, to, amount, out);
    }

    function quote(address from, address to, uint256 amount) external view returns (uint128 out) {
        Data storage s = _loadStorageSlot();

        // Use a memory cache to save gas
        Pool memory i = s.pools[from];
        Pool memory j = s.pools[to];
        (out,) = _quote(i, j, amount);
    }

    function score(address asset) external view returns (SD59x18) {
        Data storage s = _loadStorageSlot();

        Pool memory p = s.pools[asset];
        return _score(p.assets, p.liabilities);
    }

    function _quote(Pool memory i, Pool memory j, uint256 amount) internal pure returns (uint128 out, uint128 fee) {
        // Get the slippage for increasing the score of pool `i`
        SD59x18 s_i = _slippage(_score(i.assets, i.liabilities), _score(i.assets + amount, i.liabilities));
        // Get the slippage for decreasing the score of pool `j`
        SD59x18 s_j = _slippage(_score(j.assets, j.liabilities), _score(j.assets - amount, j.liabilities));

        // Calculate the multiplier as `1 - slippage`
        SD59x18 s = UNIT.sub((s_i).sub(s_j));

        // Calculate the output amount as `amount * (1 - slippage)` and safecast to uint128
        out = (amount * uint256(unwrap(s)) / 1e18).safeCastTo128();
        fee = out * FEE / 1e18;
        out -= fee;
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

    function _checkRebase(address asset, Pool memory p) internal view {
        uint256 balance = ERC20(asset).balanceOf(address(this));
        if (balance == p.assets) {
            return;
        } else if (balance > p.assets) {
            uint128 diff = (balance - p.assets).safeCastTo128();
            p.assets = p.assets + diff;
            p.liabilities += diff;
        } else {
            uint128 diff = (p.assets - balance).safeCastTo128();
            p.assets < diff ? 0 : p.assets - diff;
            p.liabilities -= diff;
        }
    }

    function _createPool(address asset) internal returns (Pool memory) {
        // Check that `asset` is the underlying() asset for the metapool or a tenderizer
        if (asset != underlying() && !Router(_router()).isTenderizer(asset)) {
            revert InvalidAsset(asset);
        }

        // Check that tenderizer is for the same underlying() asset as this Metapool
        {
            // Prevent a call to Tenderizer.asset() if `asset` is `underlying`
            address assetUnderlying;
            if (asset != underlying() && (assetUnderlying = Tenderizer(asset).asset()) != underlying()) {
                revert WrongMetapool(assetUnderlying, underlying());
            }
        }

        // Create an LP token for the new pool
        return Pool({ lpToken: LPToken(_lpToken().clone(abi.encodePacked(asset, address(this)))), assets: 0, liabilities: 0 });
    }
}
