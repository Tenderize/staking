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

import { Test, stdError } from "forge-std/test.sol";
import { TestHelpers } from "test/helpers/Helpers.sol";
import { IERC20 } from "core/interfaces/IERC20.sol";
import { TToken } from "core/tendertoken/TToken.sol";

// solhint-disable func-name-mixedcase
// solhint-disable no-empty-blocks

contract TokenSetup is TestHelpers, Test, TToken {
  uint256 public MAX_INT_SQRT = sqrt(type(uint256).max - 1);

  function name() public view override returns (string memory) {}

  function symbol() public view override returns (string memory) {}

  address public account1 = vm.addr(1);
  address public account2 = vm.addr(2);
  address public account3 = vm.addr(3);
}

// Inheriting TTokenHarness only to get events
contract TTokenTest is TokenSetup {
  function test_Metadata() public {
    assertEq(decimals(), uint8(18), "invalid decimals");
  }

  function testFuzz_ShareCalc(uint256 amount, uint256 totalShares, uint256 totalSupply) public {
    amount = bound(amount, 1, MAX_INT_SQRT);
    totalShares = bound(totalShares, 1, MAX_INT_SQRT);
    totalSupply = bound(totalSupply, 1, MAX_INT_SQRT);

    assertEq(convertToShares(amount), amount, "invalid share conversion - no shares/supply");
    assertEq(convertToAssets(amount), amount, "invalid asset conversion - no shares/supply");

    ERC20Data storage s = _loadERC20Slot();

    // zero shares
    s._totalShares = 0;
    s._totalSupply = totalSupply;
    assertEq(convertToShares(amount), amount, "invalid share conversion - no shares");
    assertEq(convertToAssets(amount), amount, "invalid asset conversion - no shares");

    // non-zero supply and shares
    s._totalShares = totalShares;
    assertEq(convertToShares(amount), (amount * totalShares) / totalSupply, "invalid share conversion");
    assertEq(convertToAssets(amount), (amount * totalSupply) / totalShares, "invalid asset conversion");

    // zero supply
    s._totalSupply = 0;
    assertEq(convertToAssets(amount), 0, "invalid asset conversion - no supply");
    vm.expectRevert();
    convertToShares(amount);
  }

  function testFuzz_BalanceOf(uint256 shares, uint256 totalShares, uint256 totalSupply) public {
    shares = bound(shares, 1, MAX_INT_SQRT / 2);
    totalShares = bound(shares, 1, MAX_INT_SQRT / 2);
    totalSupply = bound(shares, 1, MAX_INT_SQRT / 2);

    ERC20Data storage s = _loadERC20Slot();
    s.shares[account1] = shares;
    s._totalSupply = totalSupply;
    s._totalShares = totalShares;

    assertEq(balanceOf(account1), (shares * totalSupply) / totalShares, "invalid balance");
    assertEq(balanceOf(account2), 0, "invalid balance - no tokens");
  }

  function testFuzz_Approve(uint256 amountSeed) public {
    uint256 amount1 = rand(amountSeed, 0, 0, MAX_INT_SQRT);
    uint256 amount2 = rand(amountSeed, 1, 0, MAX_INT_SQRT);

    // with no prior approval
    vm.expectEmit(true, true, true, true);
    emit Approval(account1, account2, amount1);

    vm.prank(account1);
    assertTrue(this.approve(account2, amount1), "invalid return value");
    assertEq(this.allowance(account1, account2), amount1, "invalid allowance");
    assertEq(this.allowance(account1, account3), 0, "invalid allowance other account");

    // with already exisitng approval
    vm.prank(account1);
    assertTrue(this.approve(account2, amount2), "invalid return value - exisiting approval");
    assertEq(this.allowance(account1, account2), amount2, "invalid allowance - exisiting approval");
  }

  function testFuzz_Transfer(uint256 mintAmount, uint256 transferAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT);
    transferAmount = bound(transferAmount, 0, mintAmount);

    _mint(account1, mintAmount);

    vm.prank(account1);
    assertTrue(this.transfer(account2, transferAmount), "invalid return value");
    assertEq(totalSupply(), mintAmount, "invalid supply");
    assertEq(balanceOf(account1), mintAmount - transferAmount, "invalid sender balance");
    assertEq(balanceOf(account2), transferAmount, "invalid receiver balance");
  }

  function testFuzz_Transfer_RevertIfNotEnoughBalance(uint256 mintAmount, uint256 transferAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT - 1);
    transferAmount = bound(transferAmount, mintAmount + 1, MAX_INT_SQRT);

    _mint(account1, mintAmount);

    vm.prank(account1);
    vm.expectRevert(stdError.arithmeticError);
    assertFalse(this.transfer(account2, transferAmount), "invalid return value");
  }

  function testFuzz_TransferFrom(uint256 mintAmount, uint256 approveAmount, uint256 transferAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT);
    approveAmount = bound(approveAmount, 1, mintAmount);
    transferAmount = bound(transferAmount, 1, approveAmount);

    _mint(account1, mintAmount);

    vm.prank(account1);
    this.approve(account2, approveAmount);

    vm.prank(account2);
    vm.expectEmit(true, true, true, true);
    emit Transfer(account1, account3, transferAmount);

    assertTrue(this.transferFrom(account1, account3, transferAmount), "invalid return value");
    assertEq(totalSupply(), mintAmount, "invalid supply");
    assertEq(balanceOf(account1), mintAmount - transferAmount, "invalid sender balance");
    assertEq(balanceOf(account2), 0, "invalid caller balance");
    assertEq(balanceOf(account3), transferAmount, "invalid receiver balance");

    assertEq(this.allowance(account1, account2), approveAmount - transferAmount, "invalid allowance");
  }

  function testFuzz_TransferFrom_InfiniteApproval(uint256 mintAmount, uint256 transferAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT);
    transferAmount = bound(transferAmount, 1, mintAmount);

    _mint(account1, mintAmount);

    vm.prank(account1);
    this.approve(account2, type(uint256).max);
    vm.prank(account2);
    assertTrue(this.transferFrom(account1, account3, transferAmount), "invalid return value");
    assertEq(this.allowance(account1, account2), type(uint256).max, "invalid allowance");
  }

  function testFuzz_TransferFrom_RevertIfNotEnoughApproved(
    uint256 mintAmount,
    uint256 approveAmount,
    uint256 transferAmount
  ) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT - 1);
    approveAmount = bound(approveAmount, 1, mintAmount);
    transferAmount = bound(transferAmount, approveAmount + 1, MAX_INT_SQRT);

    _mint(account1, mintAmount);

    vm.prank(account1);
    this.approve(account2, approveAmount);

    vm.prank(account2);
    vm.expectRevert(stdError.arithmeticError);
    assertFalse(this.transferFrom(account1, account3, transferAmount), "invalid return value");
    assertEq(this.allowance(account1, account2), approveAmount, "invalid allowance");
  }

  function testFuzz_TransferFrom_RevertIfNotEnoughBalance(uint256 mintAmount, uint256 transferAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT - 1);
    transferAmount = bound(transferAmount, mintAmount + 1, MAX_INT_SQRT);

    _mint(account1, mintAmount);

    vm.prank(account1);
    this.approve(account2, transferAmount);

    vm.prank(account2);
    vm.expectRevert(stdError.arithmeticError);
    assertFalse(this.transferFrom(account1, account3, transferAmount), "invalid return value");
    assertEq(this.allowance(account1, account2), transferAmount, "invalid allowance");
  }

  function testFuzz_Permit(uint256 approveAmount) public {
    uint256 privateKey = 0xBEEF;
    address owner = vm.addr(privateKey);

    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      owner,
      account2,
      approveAmount,
      0,
      block.timestamp + 10000
    );

    vm.expectEmit(true, true, true, true);
    emit Approval(owner, account2, approveAmount);
    this.permit(owner, account2, approveAmount, block.timestamp + 10000, v, r, s);

    assertEq(this.allowance(owner, account2), approveAmount, "invalid allowance");
    assertEq(this.nonces(owner), 1, "invalid nonce");
  }

  function test_Permit_RevertIfInvalidSigner() public {
    uint256 privateKey = 0xBEEF;
    address signer = vm.addr(privateKey);
    uint256 amount = 10 ether;

    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      signer,
      account2,
      amount,
      0,
      block.timestamp + 10000
    );

    vm.expectRevert(abi.encodeWithSelector(TToken.InvalidSignature.selector));
    this.permit(account1, account2, amount, block.timestamp + 10000, v, r, s);
  }

  function test_Permit_RevertIfInvalidDeadline() public {
    uint256 privateKey = 0xBEEF;
    address signer = vm.addr(privateKey);
    uint256 amount = 10 ether;

    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      signer,
      account2,
      amount,
      0,
      block.timestamp
    );

    vm.expectRevert(abi.encodeWithSelector(TToken.InvalidSignature.selector));
    this.permit(signer, account2, amount, block.timestamp + 1, v, r, s);
  }

  function test_Permit_RevertIfDeadlineExpired() public {
    uint256 privateKey = 0xBEEF;
    address signer = vm.addr(privateKey);
    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      signer,
      account2,
      1 ether,
      0,
      block.timestamp
    );

    vm.warp(block.timestamp + 1);
    vm.expectRevert(abi.encodeWithSelector(TToken.InvalidSignature.selector));
    this.permit(signer, account2, 1 ether, block.timestamp, v, r, s);
  }

  function test_Permit_RevertIfInvalidNonce() public {
    uint256 privateKey = 0xBEEF;
    address signer = vm.addr(privateKey);
    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      signer,
      account2,
      1 ether,
      1,
      block.timestamp
    );

    vm.expectRevert(abi.encodeWithSelector(TToken.InvalidSignature.selector));
    this.permit(signer, account2, 1 ether, block.timestamp, v, r, s);
  }

  function test_Permit_RevertIfReplayed() public {
    uint256 privateKey = 0xBEEF;
    address signer = vm.addr(privateKey);
    uint256 amount = 1 ether;

    (uint8 v, bytes32 r, bytes32 s) = _signPermit(
      vm,
      DOMAIN_SEPARATOR(),
      privateKey,
      signer,
      account2,
      amount,
      0,
      block.timestamp + 10000
    );
    this.permit(signer, account2, amount, block.timestamp + 10000, v, r, s);

    vm.expectRevert(abi.encodeWithSelector(TToken.InvalidSignature.selector));
    this.permit(signer, account2, amount, block.timestamp + 10000, v, r, s);
  }

  function testFuzz_MintShares(uint256 shares, uint256 shares2) public {
    shares = bound(shares, 1, MAX_INT_SQRT);
    shares2 = bound(shares2, 1, MAX_INT_SQRT);

    _mintShares(account1, shares);
    ERC20Data storage s = _loadERC20Slot();
    assertEq(s.shares[account1], shares, "invalid account1 shares");
    assertEq(s._totalShares, shares, "invalid totalShares");

    _mintShares(account2, shares2);
    assertEq(s.shares[account2], shares2, "invalid account2 shares");
    assertEq(s._totalShares, shares + shares2, "invalid totalShares");
  }

  function testFuzz_BurnShares(uint256 mintShares, uint256 burnShares) public {
    mintShares = bound(mintShares, 1, MAX_INT_SQRT);
    burnShares = bound(burnShares, 1, mintShares);

    _mintShares(account1, mintShares);
    _mintShares(account2, mintShares);

    _burnShares(account1, burnShares);

    ERC20Data storage s = _loadERC20Slot();
    assertEq(s.shares[account1], mintShares - burnShares, "invalid account1 shares");
    assertEq(s.shares[account2], mintShares, "invalid account2 shares");
    assertEq(s._totalShares, mintShares * 2 - burnShares, "invalid totalShares");
  }

  function testFuzz_BurnShares_RevertIfNotEnoughShares(uint256 mintShares, uint256 burnShares) public {
    mintShares = bound(mintShares, 1, MAX_INT_SQRT - 1);
    burnShares = bound(burnShares, mintShares + 1, MAX_INT_SQRT);

    _mintShares(account1, mintShares);
    vm.expectRevert(stdError.arithmeticError);
    _burnShares(account1, burnShares);
  }

  function test_SetTotalSupply(uint256 supply) public {
    _setTotalSupply(supply);
    assertEq(totalSupply(), supply);
  }

  function testFuzz_Mint(uint256 amountSeed) public {
    uint256 amount1 = rand(amountSeed, 0, 1, MAX_INT_SQRT / 2);
    uint256 amount2 = rand(amountSeed, 1, 1, MAX_INT_SQRT / 2);

    ERC20Data storage s = _loadERC20Slot();

    _mint(account1, amount1);
    assertEq(balanceOf(account1), amount1, "invalid balance");
    assertEq(totalSupply(), amount1, "invalid supply");
    assertEq(s.shares[account1], amount1, "invalid account1 shares");
    assertEq(s._totalShares, amount1, "invalid total shares");
    assertEq(s._totalSupply, amount1, "invalid total supply");

    _mint(account2, amount2);
    assertEq(balanceOf(account2), amount2, "invalid balance");
    assertEq(totalSupply(), amount1 + amount2, "invalid supply - second mint");
    assertEq(s.shares[account2], amount2, "invalid account1 shares");
    assertEq(s._totalShares, amount1 + amount2, "invalid total shares");
    assertEq(s._totalSupply, amount1 + amount2, "invalid total supply");
  }

  function test_Mint_RevertsIfZeroShares() public {
    vm.expectRevert(abi.encodeWithSelector(TToken.ZeroShares.selector));
    _mint(account1, 0);
  }

  function testFuzz_Burn(uint256 mintAmount, uint256 burnAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT / 2);
    burnAmount = bound(burnAmount, 1, mintAmount);

    _mint(account1, mintAmount);
    _mint(account2, mintAmount);
    _burn(account1, burnAmount);

    ERC20Data storage s = _loadERC20Slot();
    assertEq(balanceOf(account1), mintAmount - burnAmount, "invalid account1 balance");
    assertEq(balanceOf(account2), mintAmount, "invalid account2 balance");
    assertEq(totalSupply(), mintAmount * 2 - burnAmount, "invalid supply");
    assertEq(s._totalShares, mintAmount * 2 - burnAmount, "invalid total shares");
    assertEq(s._totalSupply, mintAmount * 2 - burnAmount, "invalid total supply");
  }

  function testFuzz_Burn_RevertIfNotEnoughBalance(uint256 mintAmount, uint256 burnAmount) public {
    mintAmount = bound(mintAmount, 1, MAX_INT_SQRT / 2);
    burnAmount = bound(burnAmount, mintAmount + 1, MAX_INT_SQRT);

    _mint(account1, mintAmount);
    vm.expectRevert(stdError.arithmeticError);
    _burn(account1, burnAmount);
  }

  function test_Burn_RevertIfZeroShares() public {
    vm.expectRevert(abi.encodeWithSelector(TToken.ZeroShares.selector));
    _burn(account1, 0);
  }

  function test_Burn_RevertIfZeroTotalSupply(uint256 amount, uint256 totalShares) public {
    amount = bound(amount, 1, MAX_INT_SQRT);
    totalShares = bound(totalShares, 1, MAX_INT_SQRT);
    ERC20Data storage s = _loadERC20Slot();
    s._totalShares = totalShares;
    s._totalSupply = 0;

    vm.expectRevert();
    _burn(account1, amount);
  }
}
