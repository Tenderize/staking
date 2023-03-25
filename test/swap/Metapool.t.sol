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
import { SafeCastLib } from "solmate/utils/SafeCastLib.sol";
import { Metapool, Pool, _score, _slippage } from "core/swap/Metapool.sol";
import { LPToken } from "core/swap/LpToken.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";
import { SD59x18, sd, pow, fromSD59x18, E, wrap, unwrap, UNIT, sub } from "prb-math/SD59x18.sol";

contract MetaPoolTest is Test {
    using ClonesWithImmutableArgs for address;
    using SafeCastLib for uint256;

    MockERC20 tokenA;
    MockERC20 tokenB;

    SD59x18 K;
    SD59x18 N;

    Metapool mp;

    address router = vm.addr(1333);

    function setUp() public {
        tokenA = new MockERC20("Token A", "TKA", 18);
        tokenB = new MockERC20("Token B", "TKB", 18);

        // default mock calls
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
        vm.mockCall(address(tokenB), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(address(tokenA)));

        mp = Metapool(address(new Metapool()).clone(abi.encodePacked(address(tokenA), router, address(new LPToken()))));

        K = mp.K();
        N = mp.N();
    }

    function testFuzz_Deposit(uint128 amount) public {
        tokenA.mint(address(this), amount);
        tokenA.approve(address(mp), amount);

        mp.deposit(address(tokenA), amount);
        assertEq(mp.totalAssets(), amount);
        assertEq(mp.totalLiabilities(), amount);
        Pool memory a = mp.pool(address(tokenA));
        assertEq(a.assets, amount);
        assertEq(a.liabilities, amount);
        assertEq(a.lpToken.balanceOf(address(this)), amount);
        assertEq(a.lpToken.totalSupply(), amount);
    }

    function test_Deposit_Error_InvalidAsset() public {
        tokenB.mint(address(this), 1000);
        tokenB.approve(address(mp), 1000);

        vm.clearMockedCalls();
        vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(false));
        vm.expectCall(router, abi.encodeCall(Router.isTenderizer, address(tokenB)));
        vm.expectRevert(abi.encodeWithSelector(Metapool.InvalidAsset.selector, address(tokenB)));

        mp.deposit(address(tokenB), 1000);
    }

    function testDeposit_Revert_InsufficientApproval() public {
        tokenA.mint(address(this), 1000);

        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));

        mp.deposit(address(tokenA), 1000);
    }

    function testDeposit_Revert_InsufficientBalance() public {
        tokenA.mint(address(this), 1000);
        tokenA.approve(address(mp), 1000);

        vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));

        mp.deposit(address(tokenA), 1001);
    }

    function testFuzz_Withdraw(uint128 deposit, uint128 withdraw) public {
        deposit = uint128(bound(deposit, 1, type(uint128).max));
        vm.assume(withdraw <= deposit);
        tokenA.mint(address(this), deposit);
        tokenA.approve(address(mp), deposit);

        mp.deposit(address(tokenA), deposit);

        Pool memory a = mp.pool(address(tokenA));
        uint256 lpBurn = withdraw * a.lpToken.totalSupply() / a.liabilities;

        mp.withdraw(address(tokenA), withdraw);

        a = mp.pool(address(tokenA));
        assertEq(mp.totalAssets(), deposit - withdraw, "invalid total assets");
        assertEq(mp.totalLiabilities(), deposit - withdraw, "invalid total liabilities");
        assertEq(a.assets, deposit - withdraw, "invalid assets");
        assertEq(a.liabilities, deposit - withdraw, "invalid liabilities");
        assertEq(a.lpToken.balanceOf(address(this)), deposit - lpBurn, "invalid LP balance");
        assertEq(a.lpToken.totalSupply(), deposit - lpBurn, "invalid LP total supply");
    }

    function testWithdraw_Error_InsufficientAssets() public {
        tokenA.mint(address(this), 1000);
        tokenA.approve(address(mp), 1000);

        mp.deposit(address(tokenA), 1000);

        vm.expectRevert(abi.encodeWithSelector(Metapool.InsufficientAssets.selector, 1001, 1000));

        mp.withdraw(address(tokenA), 1001);
    }

    function testWithdraw_Error_LpBurnExceedsBalance() public {
        tokenA.mint(address(this), 1000);
        tokenA.approve(address(mp), 1000);

        mp.deposit(address(tokenA), 1000);

        vm.expectRevert(stdError.arithmeticError);
        vm.prank(vm.addr(1337));
        mp.withdraw(address(tokenA), 1);
    }

    function testFuzz_WithdrawOther(uint128 deposit) public {
        vm.assume(deposit > 5000);
        deposit = 10 ether;
        tokenA.mint(address(this), deposit);
        tokenA.approve(address(mp), deposit);

        tokenB.mint(address(this), deposit);
        tokenB.approve(address(mp), deposit);

        mp.deposit(address(tokenA), deposit);
        mp.deposit(address(tokenB), deposit);

        uint128 swapAmount = uint128(bound(deposit, 50, deposit / 5));
        uint128 withdrawAmount = uint128(bound(swapAmount, 1, swapAmount));

        // Make a swap to offset the balance of the 2 Pools
        tokenA.mint(address(this), swapAmount);
        tokenA.approve(address(mp), swapAmount);
        mp.swap(address(tokenA), address(tokenB), swapAmount, 0);

        Pool memory b = mp.pool(address(tokenB));
        Pool memory a = mp.pool(address(tokenA));
        uint128 aL = a.liabilities;
        uint128 aA = a.assets;
        uint128 bA = b.assets;
        uint128 bL = b.liabilities;

        uint256 lpTokens = b.lpToken.totalSupply() - withdrawAmount * b.lpToken.totalSupply() / bL;

        SD59x18 sl = _slippage(_score(aA, aL), _score(aA - withdrawAmount, aL), K, N);

        sl = UNIT.sub(sl);

        uint128 outA = (withdrawAmount * uint256(unwrap(sl)) / 1e18).safeCastTo128();

        // withdraw from tokenB using tokenA
        mp.withdrawOther(address(tokenB), address(tokenA), withdrawAmount, outA);

        a = mp.pool(address(tokenA));
        b = mp.pool(address(tokenB));

        assertEq(b.lpToken.balanceOf(address(this)), lpTokens, "invalid LP balance");
        assertEq(b.lpToken.totalSupply(), lpTokens, "invalid LP total supply");
        assertEq(a.assets, aA - outA, "invalid A assets");
        assertEq(a.liabilities, aL, "invalid A liabilities");
        assertEq(b.assets, bA, "invalid B assets");
        assertEq(b.liabilities, bL - withdrawAmount, "invalid B liabilities");
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
        // uint128 minOut = mp.quote(address(tokenA), address(tokenB), 0.03 ether);
        // uint128 out = mp.swap(address(tokenA), address(tokenB), 0.03 ether, minOut);
        // console.log("out from swap ", out);
        // uint128 quoteNext = mp.quote(address(tokenB), address(tokenA), 0.03 ether);
        // console.log("Quote for next swap ", quoteNext);
        // uint128 slip = (0.03 ether - out);
        // console.log("diff ", slip - (quoteNext - 0.03 ether));
    }
}
