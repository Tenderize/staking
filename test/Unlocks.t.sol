// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Router } from "core/router/Router.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { IERC20Metadata } from "core/interfaces/IERC20.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";
import "forge-std/console2.sol";

import "forge-std/Test.sol";

// solhint-disable func-name-mixedcase
contract UnlockTest is Test {
  Unlocks private unlocks;
  address private receiver = vm.addr(0xf00);
  address private asset = vm.addr(0xb00);
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

    vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));
    unlocks.createUnlock(receiver, 1);
  }

  function test_createUnlock_RevertIf_TooLargeId() public {
    mockIsTenderizer(true);

    vm.expectRevert(stdError.arithmeticError);
    unlocks.createUnlock(receiver, type(uint96).max + 1);
  }

  function test_useUnlock_Success() public {
    mockIsTenderizer(true);
    uint256 tokenId = unlocks.createUnlock(receiver, 1);
    uint256 balanceBefore = unlocks.balanceOf(receiver);

    unlocks.useUnlock(receiver, 1);

    assertEq(unlocks.balanceOf(receiver), balanceBefore - 1, "user balance should decrease by 1");
    vm.expectRevert("NOT_MINTED");
    unlocks.ownerOf(tokenId);
  }

  function test_useUnlock_RevertIf_NotATenderizer() public {
    mockIsTenderizer(true);
    unlocks.createUnlock(receiver, 1);

    vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));
    mockIsTenderizer(false);
    unlocks.useUnlock(receiver, 1);
  }

  function test_useUnlock_RevertIf_TooLargeId() public {
    vm.expectRevert(stdError.arithmeticError);
    unlocks.useUnlock(receiver, type(uint96).max + 1);
  }

  function test_tokenURI_Success() public {
    mockIsTenderizer(true);
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.symbol.selector), abi.encode("tGRT"));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.previewWithdraw.selector), abi.encode(100));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.unlockMaturity.selector), abi.encode(1000));
    vm.mockCall(address(this), abi.encodeWithSelector(Tenderizer.name.selector), abi.encode("tender GRT"));
    vm.mockCall(address(this), abi.encodeWithSelector(TenderizerImmutableArgs.asset.selector), abi.encode(asset));
    vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.name.selector), abi.encode("Graph"));
    vm.mockCall(asset, abi.encodeWithSelector(IERC20Metadata.symbol.selector), abi.encode("GRT"));

    uint256 tokenId = unlocks.createUnlock(receiver, 1);

    assertEq(
      unlocks.tokenURI(tokenId),
      // solhint-disable-next-line max-line-length
      "data:application/json;base64,eyJuYW1lIjogIlRlbmRlckxvY2sgIzgxNzY5MDAzNTEwMjgxMzA0NjY5ODA1OTg1MTkwOTAyMDI5NDM0NDA5MTI0MzkzNTgxODc4MDg0MzkwMDMwMTQxMDcxMDg0NzQ4ODAxIiwgImRlc2NyaXB0aW9uIjogIlRlbmRlckxvY2sgZnJvbSBodHRwczovL3RlbmRlcml6ZS5tZSByZXByZXNlbnRzIHN0YWtlZCBFUkMyMCB0b2tlbnMgZHVyaW5nIHRoZSB1bmJvbmRpbmcgcGVyaW9kLCBhbmQgdGh1cyBtYWtpbmcgdGhlbSB0cmFkYWJsZS4gT3duaW5nIGEgVGVuZGVyTG9jayB0b2tlbiBtYWtlcyB0aGUgb3duZXIgZWxpZ2libGUgdG8gY2xhaW0gdGhlIHRva2VucyBhdCB0aGUgZW5kIG9mIHRoZSB1bmJvbmRpbmcgcGVyaW9kLiIsICJpbWFnZSI6ICJkYXRhOmltYWdlL3N2Zyt4bWw7YmFzZTY0LDxzdmcgd2lkdGg9IjI5MCIgaGVpZ2h0PSI1MDAiIHZpZXdCb3g9IjAgMCAyOTAgNTAwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSdodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rJz5QSEpsWTNRZ2QybGtkR2c5SnpJNU1IQjRKeUJvWldsbmFIUTlKelV3TUhCNEp5Qm1hV3hzUFNjak1EQXdNREF3Snk4K1BIUmxlSFFnZUQwbk1UQW5JSGs5SnpJd0p6NTBSMUpVUEM5MFpYaDBQangwWlhoMElIZzlJakV3SWlCNVBTSTBNQ0krTVRBd1BDOTBaWGgwUGp4MFpYaDBJSGc5SWpFd0lpQjVQU0kyTUNJK01UQXdNRHd2ZEdWNGRENDhkR1Y0ZENCNFBTSXhNQ0lnZVQwaU9EQWlQamd4TnpZNU1EQXpOVEV3TWpneE16QTBOalk1T0RBMU9UZzFNVGt3T1RBeU1ESTVORE0wTkRBNU1USTBNemt6TlRneE9EYzRNRGcwTXprd01ETXdNVFF4TURjeE1EZzBOelE0T0RBeFBDOTBaWGgwUGp3dmMzWm5QZz09IiwiYXR0cmlidXRlcyI6W3sidHJhaXRfdHlwZSI6ICJtYXR1cml0eSIsICJ2YWx1ZSI6MTAwMH0seyJ0cmFpdF90eXBlIjogImFtb3VudCIsICJ2YWx1ZSI6MTAwfSx7InRyYWl0X3R5cGUiOiAidW5kZXJseWluZ1Rva2VuIiwgInZhbHVlIjoiR3JhcGgifSx7InRyYWl0X3R5cGUiOiAidW5kZXJseWluZ1N5bWJvbCIsICJ2YWx1ZSI6IkdSVCJ9LHsidHJhaXRfdHlwZSI6ICJ0b2tlbiIsICJ2YWx1ZSI6InRlbmRlciBHUlQifSx7InRyYWl0X3R5cGUiOiAic3ltYm9sIiwgInZhbHVlIjoidEdSVCJ9XX0="
    );
  }

  function test_tokenURI_RevertIf_IdDoesntExist() public {
    vm.expectRevert("NOT_MINTED");
    unlocks.tokenURI(1);
  }

  // helpers
  function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
    return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
  }

  function mockIsTenderizer(bool v) private {
    vm.mockCall(router, abi.encodeWithSelector(Router.isTenderizer.selector), abi.encode(v));
  }
}
