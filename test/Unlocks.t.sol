// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";
import "forge-std/Test.sol";

// solhint-disable func-name-mixedcase
contract UnlockTest is Test {
  Unlocks internal unlocks;
  address internal receiver = vm.addr(0xf00);

  function setUp() public {
    unlocks = new Unlocks(address(this));
  }

  function testCreateUnlock_SuccessReturnsEncodedTokenId() public {
    uint256 tokenId = unlocks.createUnlock(receiver, 1);
    (address tenderizer, uint256 decodedLockIndex) = _decodeTokenId(tokenId);

    assertEq(decodedLockIndex, 1);
    assertEq(address(uint160(tenderizer)), address(this));
  }

  function testCreateUnlock_SuccessIncreasesUserBalance() public {
    uint256 balanceBefore = unlocks.balanceOf(receiver);
    unlocks.createUnlock(receiver, 1);

    assertEq(unlocks.balanceOf(receiver), balanceBefore + 1, "user balance should increase by 1");
  }

  function testCreateUnlock_SuccessSetsTokenOwnership() public {
    uint256 tokenId = unlocks.createUnlock(receiver, 1);

    assertEq(unlocks.ownerOf(tokenId), receiver, "owner should be the receiver");
  }

  function testCreateUnlock_FailureNotATenderizer() public {
    vm.prank(address(receiver));

    // TODO: how to expect specific error events
    vm.expectRevert();
    uint256 tokenId = unlocks.createUnlock(receiver, 1);
  }

  function testCreateUnlock_FailureTooLargeId() public {
    vm.expectRevert(stdError.arithmeticError);
    unlocks.createUnlock(receiver, type(uint96).max + 1);
  }

  function testUseUnlock_SuccessDecreasesUserBalance() public {
    unlocks.createUnlock(receiver, 1);
    uint256 balanceBefore = unlocks.balanceOf(receiver);

    unlocks.useUnlock(receiver, 1);

    assertEq(unlocks.balanceOf(receiver), balanceBefore - 1, "user balance should decrease by 1");
  }

  function testUseUnlock_SuccessRemovesTokenOwnership() public {
    uint256 tokenId = unlocks.createUnlock(receiver, 1);
    unlocks.useUnlock(receiver, 1);

    vm.expectRevert("NOT_MINTED");
    unlocks.ownerOf(tokenId);
  }

  function testUseUnlock_FailureNotATenderizer() public {
    unlocks.createUnlock(receiver, 1);

    // TODO: how to expect specific error events
    vm.expectRevert();
    vm.prank(address(receiver));
    unlocks.useUnlock(receiver, 1);
  }

  function testUseUnlock_FailureTooLargeId() public {
    vm.expectRevert(stdError.arithmeticError);
    unlocks.useUnlock(receiver, type(uint96).max + 1);
  }

  // helpers
  function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
    return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
  }

  // Router mock calls
  function isTenderizer(address tenderizer) external view returns (bool) {
    return tenderizer == address(this);
  }
}
