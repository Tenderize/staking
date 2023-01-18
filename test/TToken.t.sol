// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";
import { PRBTest } from "test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MockTToken } from "mocks/MockTToken.sol";

// solhint-disable func-name-mixedcase

contract TokenSetup is PRBTest, StdCheats {
  MockTToken internal tToken;

  // TODO: Get from ERC20
  event Approval(address indexed owner, address indexed spender, uint256 amount);
  event Transfer(address indexed from, address indexed to, uint256 amount);
  bytes32 constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  address account1 = address(0x1234);
  address account2 = address(0x5678);
  address account3 = address(0x9ABC);

  uint256 mintAmount = 10e5 ether;

  function setUp() public {
    tToken = new MockTToken();
  }
}

contract TTokenTest is TokenSetup {
  function test_Metadata() public {
    assertEq(tToken.name(), "MockTenderToken");
    assertEq(tToken.symbol(), "MTT");
    assertEq(tToken.decimals(), uint8(18));
  }

  function test_ShareCalc_WithNoShares() public {
    assertEq(tToken.convertToShares(10), 10);
    assertEq(tToken.convertToAssets(10), 10);
  }

  function test_ShareCalc_WithShares() public {
    tToken.mint(address(0xBEEF), 10);
    assertEq(tToken.convertToShares(10), 10);
    assertEq(tToken.convertToAssets(10), 10);
  }

  function test_ShareCalc_AfterIncreasingAssets() public {
    tToken.mint(address(0xBEEF), 10);
    tToken.setTotalAssets(20);
    assertEq(tToken.convertToShares(10), 5);
    assertEq(tToken.convertToAssets(10), 20);
    assertEq(tToken.balanceOf(address(0xBEEF)), 20);
  }

  function test_ShareCalc_AfterReducingAssets() public {
    tToken.mint(address(0xBEEF), 10);
    tToken.setTotalAssets(5);
    assertEq(tToken.convertToShares(10), 20);
    assertEq(tToken.convertToAssets(10), 5);
    assertEq(tToken.balanceOf(address(0xBEEF)), 5);
  }

  function test_Approve(uint256 amount) public {
    vm.assume(amount > 0);

    vm.expectEmit(true, true, false, false);
    emit Approval(account1, account1, amount);

    vm.prank(account1);
    tToken.approve(account1, amount);

    assertEq(tToken.allowance(account1, account1), amount);
  }

  function test_Transfer(uint256 amount) public {
    vm.assume(mintAmount > amount);
    tToken.mint(address(account1), mintAmount);
    tToken.mint(address(account2), mintAmount);

    vm.expectEmit(true, true, true, false);
    emit Transfer(account1, account2, amount);

    vm.prank(account1);
    assertEq(tToken.transfer(account2, amount), true);

    assertEq(tToken.balanceOf(account1), mintAmount - amount);
    assertEq(tToken.balanceOf(account2), mintAmount + amount);
    assertEq(tToken.balanceOf(account3), 0);
  }

  function test_Transfer_NotEnoughBalance() public {
    tToken.mint(account1, mintAmount);
    vm.expectRevert(); // TODO: Assert underflow
    tToken.transfer(account2, mintAmount + 1);
  }

  function test_TransferFrom(uint256 approveAmount, uint256 transferAmount) public {
    vm.assume(transferAmount < mintAmount);
    vm.assume(transferAmount <= approveAmount);
    vm.assume(transferAmount > 0);

    tToken.mint(account1, mintAmount);
    vm.prank(account1);
    tToken.approve(account2, approveAmount);

    vm.expectEmit(true, true, true, false);
    emit Transfer(account1, account3, transferAmount);

    vm.prank(account2);
    assertEq(tToken.transferFrom(account1, account3, transferAmount), true);

    assertEq(tToken.balanceOf(account1), mintAmount - transferAmount);
    assertEq(tToken.balanceOf(account2), 0);
    assertEq(tToken.balanceOf(account3), transferAmount);

    assertAlmostEq(tToken.allowance(account1, account2), approveAmount - transferAmount, 10);
  }

  function test_TransferFrom_NotEnoughApproved() public {
    tToken.mint(account1, mintAmount);
    vm.prank(account1);
    tToken.approve(account2, 10 ether);
    vm.prank(account2);
    vm.expectRevert(); // TODO: Assert underflow
    tToken.transferFrom(account1, account3, 10 ether + 1);
  }

  function test_Permit(uint256 approveAmount) public {
    uint256 privateKey = 0xBEEF;
    address owner = vm.addr(privateKey);

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          tToken.DOMAIN_SEPARATOR(),
          keccak256(abi.encode(PERMIT_TYPEHASH, owner, account2, approveAmount, 0, block.timestamp + 10000))
        )
      )
    );

    vm.expectEmit(true, true, false, false);
    emit Approval(owner, account2, approveAmount);

    tToken.permit(owner, account2, approveAmount, block.timestamp + 10000, v, r, s);

    assertEq(tToken.allowance(owner, account2), approveAmount);
    assertEq(tToken.nonces(owner), 1);
  }

  function testPermit_InvalidSigner(uint256 approveAmount) public {
    uint256 privateKey = 0xBEEF;

    (uint8 v, bytes32 r, bytes32 s) = vm.sign(
      privateKey,
      keccak256(
        abi.encodePacked(
          "\x19\x01",
          tToken.DOMAIN_SEPARATOR(),
          keccak256(abi.encode(PERMIT_TYPEHASH, account1, account2, approveAmount, 0, block.timestamp + 10000))
        )
      )
    );

    vm.expectRevert("INVALID_SIGNER");
    tToken.permit(account1, account2, approveAmount, block.timestamp + 10000, v, r, s);
  }

  function testPermit_DeadlineExpired() public {
    vm.expectRevert("PERMIT_DEADLINE_EXPIRED");

    tToken.permit(account1, account2, 10 ether, block.timestamp - 1, 0, 0, 0);
  }
}
