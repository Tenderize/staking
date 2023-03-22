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

import { Metapool } from "core/swap/Pool.sol";
import { LPToken } from "core/swap/LpToken.sol";
import { SD59x18, sd, pow, fromSD59x18, E, wrap, unwrap } from "prb-math/SD59x18.sol";

contract MetaPoolTest is Test {
    MockERC20 tokenA;
    MockERC20 tokenB;

    Metapool pool;

    address router = vm.addr(1333);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        pool = new Metapool(address(tokenA), address(new LPToken()), router);
    }

    function test_Deposit() public {
        tokenA.mint(address(this), 1000);
        tokenA.approve(address(pool), 1000);

        pool.deposit(address(tokenA), 1000);
        assertEq(pool.totalAssets(), 1000);
        assertEq(pool.totalLiabilities(), 1000);
        assertEq(pool.getPool(address(tokenA)).assets, 1000);
        assertEq(pool.getPool(address(tokenA)).liabilities, 1000);
        assertEq(pool.getPool(address(tokenA)).lpToken.totalSupply(), 1000);

        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));

        tokenB.mint(address(this), 1000);
        tokenB.approve(address(pool), 1000);
        vm.expectCall(router, abi.encodeCall(Router.isTenderizer, address(tokenB)));

        pool.deposit(address(tokenB), 1000);
        assertEq(pool.totalAssets(), 2000);
        assertEq(pool.totalLiabilities(), 2000);
        assertEq(pool.getPool(address(tokenB)).assets, 1000);
        assertEq(pool.getPool(address(tokenB)).liabilities, 1000);
        assertEq(pool.getPool(address(tokenB)).lpToken.totalSupply(), 1000);
    }

    function test_Deposit_ErrorInvalidAsset() public {
        tokenB.mint(address(this), 1000);
        tokenB.approve(address(pool), 1000);

        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(false));
        vm.expectCall(router, abi.encodeCall(Router.isTenderizer, address(tokenB)));
        vm.expectRevert(abi.encodeWithSelector(Metapool.InvalidAsset.selector, address(tokenB)));

        pool.deposit(address(tokenB), 1000);
    }

    function test_Swap() public {
        // Set Up
        tokenA.mint(address(this), 5 ether);
        tokenA.approve(address(pool), 5 ether);
        pool.deposit(address(tokenA), 5 ether);
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));

        tokenB.mint(address(this), 0.33 ether);
        tokenB.approve(address(pool), 0.33 ether);
        pool.deposit(address(tokenB), 0.33 ether);

        tokenA.mint(address(this), 0.22 ether);
        tokenA.approve(address(pool), 0.22 ether);
        uint256 minOut = pool.quote(address(tokenA), address(tokenB), 0.12 ether);
        uint256 out = pool.swap(address(tokenA), address(tokenB), 0.12 ether, minOut);
        console.log("out from swap ", out);
        uint256 quoteNext = pool.quote(address(tokenB), address(tokenA), 0.12 ether);
        console.log("Quote for next swap ", quoteNext);
        uint256 slip = (0.12 ether - out);
        console.log("diff ", slip - (quoteNext - 0.12 ether));
    }
}
