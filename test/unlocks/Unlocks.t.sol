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

pragma solidity >=0.8.19;

import { Test, stdError } from "forge-std/Test.sol";

import { IERC20Metadata } from "core/interfaces/IERC20.sol";
import { Adapter } from "core/adapters/Adapter.sol";
import { Renderer } from "core/unlocks/Renderer.sol";
import { Registry } from "core/registry/Registry.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { TenderizerImmutableArgs } from "core/tenderizer/TenderizerBase.sol";
import { Unlocks, Metadata } from "core/unlocks/Unlocks.sol";

// solhint-disable func-name-mixedcase
contract UnlockTest is Test {
    Unlocks private unlocks;
    address private receiver = vm.addr(1);
    address private asset = vm.addr(2);
    address private registry = vm.addr(3);
    address private renderer = vm.addr(4);
    address private impostor = vm.addr(5);
    address private validator = vm.addr(6);
    address private adapter = vm.addr(7);

    function setUp() public {
        unlocks = new Unlocks(registry, renderer);
        vm.etch(adapter, bytes("code"));
    }

    function test_Metadata() public {
        assertEq(unlocks.name(), "TenderUnlocks");
        assertEq(unlocks.symbol(), "UNLOCK");
    }

    function testFuzz_createUnlock_Success(address owner, uint256 lockId) public {
        lockId = bound(lockId, 0, type(uint96).max);
        vm.assume(owner != address(0) && owner != registry && !_isContract(owner));
        uint256 balanceBefore = unlocks.balanceOf(owner);

        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        uint256 tokenId = unlocks.createUnlock(owner, lockId);

        (address tenderizer, uint256 decodedLockIndex) = _decodeTokenId(tokenId);
        assertEq(decodedLockIndex, lockId);
        assertEq(address(uint160(tenderizer)), address(this), "decoded address should be the test address");
        assertEq(unlocks.balanceOf(owner), balanceBefore + 1, "user balance should increase by 1");
        assertEq(unlocks.ownerOf(tokenId), owner, "owner should be the owner");
    }

    function test_createUnlock_RevertIfNotTenderizer() public {
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(false));

        vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));
        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        unlocks.createUnlock(receiver, 1);
    }

    function test_createUnlock_RevertIfTooLargeId() public {
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));

        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        vm.expectRevert(abi.encodeWithSelector(Unlocks.InvalidID.selector));
        unlocks.createUnlock(receiver, 1 << 96);
    }

    function testFuzz_useUnlock_Success(address owner, uint256 lockId) public {
        lockId = bound(lockId, 0, type(uint96).max);
        vm.assume(owner != address(0) && owner != registry && !_isContract(owner));
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        uint256 tokenId = unlocks.createUnlock(owner, lockId);
        uint256 balanceBefore = unlocks.balanceOf(owner);

        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        unlocks.useUnlock(owner, lockId);

        assertEq(unlocks.balanceOf(owner), balanceBefore - 1, "user balance should decrease by 1");
        vm.expectRevert("NOT_MINTED");

        unlocks.ownerOf(tokenId);
    }

    function test_useUnlock_RevertIfNotTenderizer() public {
        uint256 lockId = 1;
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        unlocks.createUnlock(receiver, lockId);

        vm.expectRevert(abi.encodeWithSelector(Unlocks.NotTenderizer.selector, address(this)));

        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(false));

        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        unlocks.useUnlock(receiver, lockId);
    }

    function test_useUnlock_RevertIfNotOwnerOf() public {
        uint256 lockId = 1;
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        unlocks.createUnlock(receiver, lockId);

        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        vm.expectRevert(abi.encodeWithSelector(Unlocks.NotOwnerOf.selector, lockId, receiver, impostor));
        unlocks.useUnlock(impostor, lockId);
    }

    function test_useUnlock_RevertIfTooLargeId() public {
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));

        vm.expectRevert(abi.encodeWithSelector(Unlocks.InvalidID.selector));
        unlocks.useUnlock(receiver, 1 << 96);
    }

    function test_tokenURI_Success() public {
        uint256 lockId = 1;
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))), abi.encode(true));
        vm.expectCall(registry, abi.encodeCall(Registry.isTenderizer, (address(this))));
        uint256 tokenId = unlocks.createUnlock(receiver, lockId);

        vm.mockCall(renderer, abi.encodeCall(Renderer.json, (tokenId)), abi.encode("token uri"));
        vm.expectCall(renderer, abi.encodeCall(Renderer.json, (tokenId)));
        string memory expURI = unlocks.tokenURI(tokenId);
        assertEq(expURI, "token uri");
    }

    function test_tokenURI_RevertIfIdDoesntExist() public {
        vm.expectRevert("NOT_MINTED");
        unlocks.tokenURI(1);
    }

    function test_getMetadata() public {
        address tenderizer = address(this);
        // create an unlock
        uint256 lockId = 1337;
        vm.mockCall(registry, abi.encodeCall(Registry.isTenderizer, (tenderizer)), abi.encode(true));
        uint256 tokenId = unlocks.createUnlock(msg.sender, lockId);

        vm.mockCall(tenderizer, abi.encodeCall(TenderizerImmutableArgs.adapter, ()), abi.encode((adapter)));
        vm.mockCall(adapter, abi.encodeCall(Adapter.currentTime, ()), abi.encode((block.number + 50)));
        vm.mockCall(adapter, abi.encodeCall(Adapter.unlockTime, ()), abi.encode((100)));

        vm.mockCall(tenderizer, abi.encodeCall(Tenderizer.previewWithdraw, (lockId)), abi.encode((1 ether)));
        vm.mockCall(tenderizer, abi.encodeCall(Tenderizer.unlockMaturity, (lockId)), abi.encode((block.number + 100)));
        vm.mockCall(tenderizer, abi.encodeCall(TenderizerImmutableArgs.validator, ()), abi.encode((validator)));
        vm.mockCall(tenderizer, abi.encodeCall(TenderizerImmutableArgs.asset, ()), abi.encode((asset)));
        vm.mockCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode(("TEST")));
        vm.mockCall(asset, abi.encodeCall(IERC20Metadata.name, ()), abi.encode(("Test Token")));
        // get meta data

        Metadata memory d = unlocks.getMetadata(tokenId);

        assertEq(d.unlockId, lockId);
        assertEq(d.amount, 1 ether);
        assertEq(d.maturity, block.number + 100);
        assertEq(d.progress, 50);
        assertEq(d.symbol, "TEST");
        assertEq(d.name, "Test Token");
        assertEq(d.validator, validator);
    }

    // helpers
    function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
        return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
    }

    function _encodeTokenId(address tenderizer, uint96 id) internal pure virtual returns (uint256) {
        return uint256(bytes32(abi.encodePacked(tenderizer, id)));
    }

    function _isContract(address addr) internal view returns (bool) {
        return addr.code.length != 0;
    }
}
