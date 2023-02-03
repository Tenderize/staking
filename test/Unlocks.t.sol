// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Renderer, RendererData } from "core/unlocks/Renderer.sol";
import { Router } from "core/router/Router.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { IERC20Metadata } from "core/interfaces/IERC20.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";

import "forge-std/Test.sol";

// solhint-disable func-name-mixedcase
contract UnlockTest is Test {
  Unlocks private unlocks;
  address private receiver = vm.addr(1);
  address private asset = vm.addr(2);
  address private router = vm.addr(3);
  address private renderer = vm.addr(4);
  address private impostor = vm.addr(5);

  function setUp() public {
    unlocks = new Unlocks(router, renderer);
  }

  function test_Metadata() public {
    assertEq(unlocks.name(), "Tenderize Unlocks");
    assertEq(unlocks.symbol(), "TUNL");
  }

  function test_createUnlock_Success() public {
    uint256 unlockId = 1;
    uint256 balanceBefore = unlocks.balanceOf(receiver);
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));

    uint256 tokenId = unlocks.createUnlock(receiver, unlockId);

    (address tenderizer, uint256 decodedLockIndex) = _decodeTokenId(tokenId);
    assertEq(decodedLockIndex, unlockId, "lock index should be 1");
    assertEq(address(uint160(tenderizer)), address(this), "decoded address should be the test address");
    assertEq(unlocks.balanceOf(receiver), balanceBefore + 1, "user balance should increase by 1");
    assertEq(unlocks.ownerOf(tokenId), receiver, "owner should be the receiver");
  }

  function testFuzz_createUnlock_Success(address receiver, uint256 lockId) public {
    vm.assume(receiver != address(0));
    vm.assume(receiver != router);
    vm.assume(!_isContract(receiver));
    vm.assume(lockId < 1 << 96);
    uint256 balanceBefore = unlocks.balanceOf(receiver);
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    uint256 tokenId = unlocks.createUnlock(receiver, lockId);
    (address tenderizer, uint256 decodedLockIndex) = _decodeTokenId(tokenId);

    assertEq(decodedLockIndex, lockId, "lock index should be 1");
    assertEq(address(uint160(tenderizer)), address(this), "decoded address should be the test address");
    assertEq(unlocks.balanceOf(receiver), balanceBefore + 1, "user balance should increase by 1");
    assertEq(unlocks.ownerOf(tokenId), receiver, "owner should be the receiver");
  }

  function test_createUnlock_RevertIf_NotATenderizer() public {
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(false));

    vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));
    unlocks.createUnlock(receiver, 1);
  }

  function test_createUnlock_RevertIf_TooLargeId() public {
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));

    vm.expectRevert(stdError.arithmeticError);
    unlocks.createUnlock(receiver, type(uint96).max + 1);
  }

  function test_useUnlock_Success() public {
    uint256 lockId = 1;
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    uint256 tokenId = unlocks.createUnlock(receiver, lockId);
    uint256 balanceBefore = unlocks.balanceOf(receiver);

    unlocks.useUnlock(receiver, lockId);

    assertEq(unlocks.balanceOf(receiver), balanceBefore - 1, "user balance should decrease by 1");
    vm.expectRevert("NOT_MINTED");
    unlocks.ownerOf(tokenId);
  }

  function testFuzz_useUnlock_Success(address receiver, uint256 lockId) public {
    vm.assume(receiver != address(0));
    vm.assume(receiver != router);
    vm.assume(!_isContract(receiver));
    vm.assume(lockId < 1 << 96);
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    uint256 tokenId = unlocks.createUnlock(receiver, lockId);
    uint256 balanceBefore = unlocks.balanceOf(receiver);

    unlocks.useUnlock(receiver, lockId);

    assertEq(unlocks.balanceOf(receiver), balanceBefore - 1, "user balance should decrease by 1");
    vm.expectRevert("NOT_MINTED");

    unlocks.ownerOf(tokenId);
  }

  function test_useUnlock_RevertIf_NotATenderizer() public {
    uint256 lockId = 1;
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    unlocks.createUnlock(receiver, lockId);

    vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));

    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(false));
    unlocks.useUnlock(receiver, lockId);
  }

  function test_useUnlock_RevertIf_NotOwnerOf() public {
    uint256 lockId = 1;
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    unlocks.createUnlock(receiver, lockId);

    vm.expectRevert(abi.encodeWithSelector(Unlocks.NotOwnerOf.selector, lockId, receiver, impostor));
    unlocks.useUnlock(impostor, lockId);
  }

  function test_useUnlock_RevertIf_TooLargeId() public {
    vm.expectRevert(stdError.arithmeticError);
    unlocks.useUnlock(receiver, type(uint96).max + 1);
  }

  function test_tokenURI_Success() public {
    uint256 lockId = 1;
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(true));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.symbol.selector), abi.encode("tGRT"));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.previewWithdraw.selector), abi.encode(100));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector), abi.encode(1000));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.name.selector), abi.encode("tender GRT"));
    vm.mockCall(address(this), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(asset));
    vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.name.selector), abi.encode("Graph"));
    vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("GRT"));
    vm.mockCall(
      renderer,
      abi.encodeWithSelector(Renderer.json.selector),
      abi.encode(
        RendererData({
          amount: 100,
          maturity: 1000,
          tokenId: _encodeTokenId(address(this), uint96(lockId)),
          symbol: "tGRT",
          name: "tender GRT",
          underlyingSymbol: "GRT",
          underlyingName: "Graph"
        })
      )
    );
    uint256 tokenId = unlocks.createUnlock(receiver, lockId);

    (, uint256 decodedLockIndex) = _decodeTokenId(tokenId);

    vm.expectCall(address(this), abi.encodeCall(Tenderizer.symbol, ()));
    vm.expectCall(address(this), abi.encodeCall(Tenderizer.previewWithdraw, (decodedLockIndex)));
    vm.expectCall(address(this), abi.encodeCall(Tenderizer.unlockMaturity, (decodedLockIndex)));
    vm.expectCall(address(this), abi.encodeCall(Tenderizer.name, ()));
    vm.expectCall(address(this), abi.encodeCall(TenderizerImmutableArgs.asset, ()));
    vm.expectCall(asset, abi.encodeCall(IERC20Metadata.name, ()));
    vm.expectCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()));
    vm.expectCall(
      renderer,
      abi.encodeCall(
        Renderer.json,
        (
          RendererData({
            amount: 100,
            maturity: 1000,
            tokenId: _encodeTokenId(address(this), uint96(lockId)),
            symbol: "tGRT",
            name: "tender GRT",
            underlyingSymbol: "GRT",
            underlyingName: "Graph"
          })
        )
      )
    );
    unlocks.tokenURI(tokenId);
  }

  function test_tokenURI_RevertIf_IdDoesntExist() public {
    vm.expectRevert("NOT_MINTED");
    unlocks.tokenURI(1);
  }

  // helpers
  function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
    return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
  }

  function _encodeTokenId(address tenderizer, uint96 id) internal pure virtual returns (uint256) {
    return uint256(bytes32(abi.encodePacked(tenderizer, id)));
  }

  function _isContract(address addr) internal view returns (bool) {
    return addr.code.length > 0;
  }
}
