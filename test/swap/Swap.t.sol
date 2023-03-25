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

import { Test, stdError, console } from "forge-std/Test.sol";
import { Router } from "core/router/Router.sol";
import { MockERC20 } from "test/helpers/MockERC20.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

import { Metapool, Pool } from "core/swap/Metapool.sol";
import { LPToken } from "core/swap/LpToken.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";
import { SD59x18, sd, pow, fromSD59x18, E, wrap, unwrap } from "prb-math/SD59x18.sol";

contract MetaPoolTest is Metapool, Test {
    MockERC20 tokenA;
    MockERC20 tokenB;

    address router = vm.addr(1333);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        // default mock calls
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
        vm.mockCall(address(tokenB), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(tokenA)));
    }

    function _testQuote() internal {
        uint256 __id__ = vm.snapshot();

        vm.revertTo(__id__);
    }

    function testQuote() public {
        Data storage s = _loadStorageSlot();
        Pool storage a = s.pools[address(tokenA)];
        Pool storage b = s.pools[address(tokenB)];

        // Case 1
        a.assets = 100 ether;
        a.liabilities = 100 ether;
        b.assets = 100 ether;
        b.liabilities = 100 ether;
        s.totalAssets = a.assets + b.assets;
        s.totalLiabilities = a.liabilities + b.liabilities;

        (uint128 out,) = Metapool(address(this)).quote(address(tokenA), address(tokenB), 10 ether);
        assertEq(out, 9_710_527_972_550_683_042, "case 1 failed");

        // Case 2
        a.assets = 50 ether;
        b.assets = 160 ether;
        s.totalAssets = a.assets + b.assets;
        (out,) = Metapool(address(this)).quote(address(tokenA), address(tokenB), 10 ether);
        assertEq(out, 19_392_877_225_583_231_203, "case 2 failed");

        // Case 3
        a.assets = 353 ether;
        a.liabilities = 269 ether;
        b.assets = 10_345 ether;
        b.liabilities = 10_415 ether;
        s.totalAssets = a.assets + b.assets;
        s.totalLiabilities = a.liabilities + b.liabilities;
        (out,) = Metapool(address(this)).quote(address(tokenA), address(tokenB), 41 ether);
        assertEq(out, 39_152_097_041_008_618_632, "case 3 failed");
    }
}
