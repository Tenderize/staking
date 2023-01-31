// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Router } from "core/router/Router.sol";

import "forge-std/Test.sol";

// solhint-disable func-name-mixedcase
contract UnlockTest is Test {
  Unlocks private unlocks;
  address private receiver = vm.addr(0xf00);
  address private router = vm.addr(0xb33f);

  function setUp() public {
    unlocks = new Unlocks(router);
  }

  function test_Metadata() public {
    assertEq(unlocks.name(), "Tenderize Unlocks");
    assertEq(unlocks.symbol(), "TUNL");
  }

  function test_createUnlock_Success() public {
    uint256 balanceBefore = unlocks.balanceOf(receiver);
    mockIsTenderizer(true);
    uint256 tokenId = unlocks.createUnlock(receiver, 1);
    (address tenderizer, uint256 decodedLockIndex) = _decodeTokenId(tokenId);

    assertEq(decodedLockIndex, 1, "lock index should be 1");
    assertEq(address(uint160(tenderizer)), address(this), "decoded address should be the test address");
    assertEq(unlocks.balanceOf(receiver), balanceBefore + 1, "user balance should increase by 1");
    assertEq(unlocks.ownerOf(tokenId), receiver, "owner should be the receiver");
  }

  function test_createUnlock_RevertIf_NotATenderizer() public {
    mockIsTenderizer(false);

    // TODO: how to expect specific error events
    vm.expectRevert();
    unlocks.createUnlock(receiver, 1);
  }

  function test_createUnlock_RevertIf_TooLargeId() public {
    mockIsTenderizer(true);

    vm.expectRevert(stdError.arithmeticError);
    unlocks.createUnlock(receiver, type(uint96).max + 1);
  }

  function test_useUnlock_Success() public {
    mockIsTenderizer(true);
    unlocks.createUnlock(receiver, 1);
    uint256 balanceBefore = unlocks.balanceOf(receiver);

    unlocks.useUnlock(receiver, 1);

    assertEq(unlocks.balanceOf(receiver), balanceBefore - 1, "user balance should decrease by 1");
    vm.expectRevert("NOT_MINTED");
    unlocks.ownerOf(tokenId);
  }

  function test_useUnlock_RevertIf_NotATenderizer() public {
    mockIsTenderizer(true);
    unlocks.createUnlock(receiver, 1);

    // TODO: how to expect specific error events
    vm.expectRevert();
    mockIsTenderizer(false);
    unlocks.useUnlock(receiver, 1);
  }

  function test_useUnlock_RevertIf_TooLargeId() public {
    vm.expectRevert(stdError.arithmeticError);
    unlocks.useUnlock(receiver, type(uint96).max + 1);
  }

  // helpers
  function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
    return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
  }

  function mockIsTenderizer(bool v) private {
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(v));
  }
}
