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

import { Test } from "forge-std/Test.sol";

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { StringsUpgradeable } from "openzeppelin-contracts-upgradeable/utils/StringsUpgradeable.sol";
import { ClonesUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { UUPSTestHelper } from "test/helpers/UUPSTestHelper.sol";
import { Registry } from "core/registry/Registry.sol";
import { FACTORY_ROLE, FEE_GAUGE_ROLE, TENDERIZER_ROLE, UPGRADE_ROLE, GOVERNANCE_ROLE } from "core/registry/Roles.sol";

// solhint-disable quotes
// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls
// solhint-disable no-empty-blocks

bytes32 constant DEFAULT_ADMIN_ROLE = 0x00;

contract RegistryV3 is Registry {
    bytes32 private constant NEW_ROLE = keccak256("NEW_ROLE");

    function newFunction() public view onlyRole(NEW_ROLE) returns (string memory) {
        return "newFunction called";
    }
}

contract RegistryUpgradeTest is UUPSTestHelper {
    address private gov = vm.addr(3);
    address private tenderizer = vm.addr(4);
    address private unlocks = vm.addr(5);

    constructor() UUPSTestHelper(address(new Registry()), abi.encodeCall(Registry.initialize, (tenderizer, unlocks))) { }

    function test_InitialRoles() public {
        assertEq(Registry(address(proxy)).hasRole(UPGRADE_ROLE, owner), true);
        assertEq(Registry(address(proxy)).hasRole(GOVERNANCE_ROLE, owner), true);
        assertEq(Registry(address(proxy)).hasRole(FEE_GAUGE_ROLE, owner), true);

        assertEq(Registry(address(proxy)).getRoleAdmin(GOVERNANCE_ROLE), GOVERNANCE_ROLE);
        assertEq(Registry(address(proxy)).getRoleAdmin(FACTORY_ROLE), GOVERNANCE_ROLE);
        assertEq(Registry(address(proxy)).getRoleAdmin(FEE_GAUGE_ROLE), FEE_GAUGE_ROLE);
        assertEq(Registry(address(proxy)).getRoleAdmin(TENDERIZER_ROLE), Registry(address(proxy)).DEFAULT_ADMIN_ROLE());
        assertEq(Registry(address(proxy)).getRoleAdmin(UPGRADE_ROLE), UPGRADE_ROLE);
    }

    function test_upgradeTo_RevertIfNotOwner() public {
        vm.startPrank(nonAuthorized);

        Registry registryV2 = new Registry();

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(nonAuthorized),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(UPGRADE_ROLE), 32)
            )
        );
        Registry(address(proxy)).upgradeTo(address(registryV2));
        vm.stopPrank();
    }

    function test_TransferUpgradeRoleToUpgradeWithGov() public {
        Registry registryV2 = new Registry();
        vm.startPrank(owner);
        Registry(address(proxy)).grantRole(UPGRADE_ROLE, gov);
        Registry(address(proxy)).revokeRole(UPGRADE_ROLE, owner);

        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(owner),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(UPGRADE_ROLE), 32)
            )
        );
        Registry(address(proxy)).upgradeTo(address(registryV2));

        vm.stopPrank();

        vm.startPrank(gov);

        bytes32 proxySlotBefore = vm.load(address(proxy), IMPL_SLOT);
        assertEq(proxySlotBefore, bytes32(uint256(uint160(address(currentVersion)))));

        Registry(address(proxy)).upgradeTo(address(registryV2));

        bytes32 proxySlotAfter = vm.load(address(proxy), IMPL_SLOT);
        assertEq(proxySlotAfter, bytes32(uint256(uint160(address(registryV2)))));
        vm.stopPrank();
    }

    function testFuzz_RevokeUpgradeRole_DisablesUpgrades(address user) public {
        vm.startPrank(owner);
        Registry(address(proxy)).revokeRole(UPGRADE_ROLE, owner);
        vm.stopPrank();

        Registry registryV2 = new Registry();

        vm.startPrank(user);
        vm.expectRevert(
            abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(user),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(UPGRADE_ROLE), 32)
            )
        );
        Registry(address(proxy)).upgradeTo(address(registryV2));
        vm.stopPrank();
    }
}

contract InitializedRegistry is Registry {
    constructor() Registry() {
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        _grantRole(FEE_GAUGE_ROLE, msg.sender);

        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(FACTORY_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(FEE_GAUGE_ROLE, FEE_GAUGE_ROLE);
        _setRoleAdmin(TENDERIZER_ROLE, DEFAULT_ADMIN_ROLE);
        // Only allow UPGRADE_ROLE to add new UPGRADE_ROLE memebers
        // If all members of UPGRADE_ROLE are revoked, contract upgradability is revoked
        _setRoleAdmin(UPGRADE_ROLE, UPGRADE_ROLE);
    }
}

contract RegistryTest is Test {
    Registry private registry;

    address private owner = vm.addr(1);
    address private account = vm.addr(2);
    address private adapter = vm.addr(3);
    address private asset = vm.addr(4);
    address private tenderizer = vm.addr(5);
    address private factory = vm.addr(5);
    address private feeGauge = vm.addr(6);

    event AdapterRegistered(address indexed asset, address indexed adapter);
    event NewTenderizer(address indexed asset, address indexed validator, address tenderizer);
    event FeeAdjusted(address indexed asset, uint256 newFee, uint256 oldFee);
    event TreasurySet(address indexed treasury);

    function setUp() public {
        vm.startPrank(owner);
        registry = new InitializedRegistry();
        vm.stopPrank();
    }

    function test_RegisterAdapter() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit AdapterRegistered(asset, adapter);
        registry.registerAdapter(asset, adapter);
        assertEq(registry.adapter(asset), adapter);
    }

    function test_RegisterAdapter_RevertIfNotGov() public {
        vm.prank(account);
        vm.expectRevert();
        registry.registerAdapter(asset, adapter);
    }

    function test_RegisterTenderizer() public {
        vm.prank(owner);
        registry.grantRole(FACTORY_ROLE, factory);

        vm.prank(factory);
        vm.expectEmit(true, true, true, true);
        emit NewTenderizer(asset, account, tenderizer);
        registry.registerTenderizer(asset, account, tenderizer);
        assertEq(registry.hasRole(TENDERIZER_ROLE, tenderizer), true);
    }

    function test_RegisterTenderizer_RevertIfNotFactory() public {
        vm.prank(owner);
        vm.expectRevert();
        registry.registerTenderizer(asset, account, tenderizer);
    }

    function test_SetFee() public {
        uint96 fee1 = 100;
        uint96 fee2 = 200;

        vm.prank(owner);
        registry.grantRole(FEE_GAUGE_ROLE, feeGauge);

        vm.startPrank(feeGauge);
        registry.setFee(asset, fee1);
        vm.expectEmit(true, true, true, true);
        emit FeeAdjusted(asset, fee2, fee1);
        registry.setFee(asset, fee2);
        assertEq(registry.fee(asset), fee2);
        vm.stopPrank();
    }

    function test_SetFee_RevertIfNotFeeGauge() public {
        vm.prank(account);
        vm.expectRevert();
        registry.setFee(asset, 100);
    }

    function test_SetTreasury() public {
        vm.prank(owner);
        vm.expectEmit(true, true, true, true);
        emit TreasurySet(account);
        registry.setTreasury(account);
        assertEq(registry.treasury(), account);
    }

    function test_SetTreasury_RevertIfNotGov() public {
        vm.prank(account);
        vm.expectRevert();
        registry.setTreasury(account);
    }
}
