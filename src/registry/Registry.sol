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

import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract Registry is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    bytes32 private constant FACTORY_ROLE = keccak256("FACTORY_ROLE");
    bytes32 private constant FEE_GAUGE_ROLE = keccak256("FEE_GAUGE_ROLE");
    bytes32 private constant TENDERIZER_ROLE = keccak256("TENDERIZER_ROLE");
    bytes32 private constant UPGRADE_ROLE = keccak256("UPGRADE_ROLE");
    bytes32 private constant GOVERNANCE_ROLE = keccak256("GOVERNANCE_ROLE");

    event AdapterRegistered(address indexed asset, address indexed adapter);
    event NewTenderizer(address indexed asset, address indexed validator, address tenderizer);
    event FeeAdjusted(address indexed asset, uint256 newFee, uint256 oldFee);
    event TreasurySet(address indexed treasury);

    struct Protocol {
        address adapter;
        uint96 fee;
    }

    struct Storage {
        mapping(address => Protocol) protocols;
        address treasury;
    }

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.registry.storage.location")) - 1;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize() public initializer {
        __AccessControl_init();
        _grantRole(UPGRADE_ROLE, msg.sender);
        _grantRole(GOVERNANCE_ROLE, msg.sender);
        _grantRole(FEE_GAUGE_ROLE, msg.sender);

        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(FACTORY_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(FEE_GAUGE_ROLE, FEE_GAUGE_ROLE);
        // Only allow UPGRADE_ROLE to add new UPGRADE_ROLE memebers
        // If all members of UPGRADE_ROLE are revoked, contract upgradability is revoked
        _setRoleAdmin(UPGRADE_ROLE, UPGRADE_ROLE);
    }

    // Getters

    function adapter(address asset) external view returns (address) {
        return _loadStorage().protocols[asset].adapter;
    }

    function fee(address asset) external view returns (uint96) {
        return _loadStorage().protocols[asset].fee;
    }

    function isTenderizer(address tenderizer) external view returns (bool) {
        return hasRole(TENDERIZER_ROLE, tenderizer);
    }

    function treasury() external view returns (address) {
        return _loadStorage().treasury;
    }

    // Setters

    function registerAdapter(address asset, address adapter) external onlyRole(GOVERNANCE_ROLE) {
        _loadStorage().protocols[asset].adapter = adapter;
        emit AdapterRegistered(asset, adapter);
    }

    function registerTenderizer(address asset, address validator, address tenderizer) external onlyRole(FACTORY_ROLE) {
        _grantRole(TENDERIZER_ROLE, tenderizer);
        emit NewTenderizer(asset, validator, tenderizer);
    }

    function setFee(address asset, uint96 fee) external onlyRole(FEE_GAUGE_ROLE) {
        Storage storage $ = _loadStorage();
        uint256 oldFee = $.protocols[asset].fee;
        $.protocols[asset].fee = fee;
        emit FeeAdjusted(asset, fee, oldFee);
    }

    function setTreasury(address treasury) external onlyRole(GOVERNANCE_ROLE) {
        _loadStorage().treasury = treasury;
        emit TreasurySet(treasury);
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADE_ROLE) { }

    function _loadStorage() internal pure returns (Storage storage s) {
        uint256 slot = STORAGE;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            s.slot := slot
        }
    }
}
