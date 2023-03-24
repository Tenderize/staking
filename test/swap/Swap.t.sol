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

import { Metapool } from "core/swap/Metapool.sol";
import { LPToken } from "core/swap/LpToken.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";
import { SD59x18, sd, pow, fromSD59x18, E, wrap, unwrap } from "prb-math/SD59x18.sol";

contract MetaPoolTest is Test {
    using ClonesWithImmutableArgs for address;

    MockERC20 tokenA;
    MockERC20 tokenB;

    Metapool mp;

    address router = vm.addr(1333);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        // default mock calls
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
        vm.mockCall(address(tokenB), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(tokenA)));

        mp = Metapool(address(new Metapool()).clone(abi.encodePacked(address(tokenA), router, address(new LPToken()))));
    }

    function test_Deposit() public {
        tokenA.mint(address(this), 1000);
        tokenA.approve(address(mp), 1000);

        mp.deposit(address(tokenA), 1000);
        assertEq(mp.totalAssets(), 1000);
        assertEq(mp.totalLiabilities(), 1000);
        assertEq(mp.pool(address(tokenA)).assets, 1000);
        assertEq(mp.pool(address(tokenA)).liabilities, 1000);
        assertEq(mp.pool(address(tokenA)).lpToken.totalSupply(), 1000);

        tokenB.mint(address(this), 1000);
        tokenB.approve(address(mp), 1000);
        vm.expectCall(router, abi.encodeCall(Router.isTenderizer, address(tokenB)));
        vm.expectCall(address(tokenB), abi.encodeCall(TenderizerImmutableArgs.asset, ()));

        mp.deposit(address(tokenB), 1000);
        assertEq(mp.totalAssets(), 2000);
        assertEq(mp.totalLiabilities(), 2000);
        assertEq(mp.pool(address(tokenB)).assets, 1000);
        assertEq(mp.pool(address(tokenB)).liabilities, 1000);
        assertEq(mp.pool(address(tokenB)).lpToken.totalSupply(), 1000);
    }

    function test_Deposit_ErrorInvalidAsset() public {
        tokenB.mint(address(this), 1000);
        tokenB.approve(address(mp), 1000);

        vm.clearMockedCalls();
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(false));
        vm.expectCall(router, abi.encodeCall(Router.isTenderizer, address(tokenB)));
        vm.expectRevert(abi.encodeWithSelector(Metapool.InvalidAsset.selector, address(tokenB)));

        mp.deposit(address(tokenB), 1000);
    }

    function test_Swap() public {
        // Set Up
        tokenA.mint(address(this), 5 ether);
        tokenA.approve(address(mp), 5 ether);
        mp.deposit(address(tokenA), 5 ether);

        tokenB.mint(address(this), 0.33 ether);
        tokenB.approve(address(mp), 0.33 ether);

        mp.deposit(address(tokenB), 0.33 ether);

        tokenA.mint(address(this), 0.22 ether);
        tokenA.approve(address(mp), 0.22 ether);
        uint128 minOut = mp.quote(address(tokenA), address(tokenB), 0.03 ether);
        uint128 out = mp.swap(address(tokenA), address(tokenB), 0.03 ether, minOut);
        console.log("out from swap ", out);
        uint128 quoteNext = mp.quote(address(tokenB), address(tokenA), 0.03 ether);
        console.log("Quote for next swap ", quoteNext);
        uint128 slip = (0.03 ether - out);
        console.log("diff ", slip - (quoteNext - 0.03 ether));
    }
}
