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

import { ERC721 } from "solmate/tokens/ERC721.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Registry } from "core/registry/Registry.sol";
import { Renderer } from "core/unlocks/Renderer.sol";

pragma solidity 0.8.17;

// solhint-disable quotes

/// @title Unlocks
/// @notice ERC721 contract for unlock tokens
/// @dev Creates an NFT for staked tokens pending unlock. Each Unlock has an amount and a maturity date.

struct Metadata {
    uint256 amount;
    uint256 maturity;
    uint256 tokenId;
    string symbol;
    string name;
    address validator;
}

contract Unlocks is ERC721 {
    Registry private immutable registry;
    Renderer private immutable renderer;

    error NotOwnerOf(uint256 id, address owner, address sender);
    error NotTenderizer(address sender);
    error InvalidID();

    modifier isValidTenderizer(address sender) {
        _isValidTenderizer(sender);
        _;
    }

    constructor(address _registry, address _renderer) ERC721("TenderUnlocks", "UNLOCK") {
        registry = Registry(_registry);
        renderer = Renderer(_renderer);
    }

    /**
     * @notice Creates a new unlock token
     * @dev Only callable by a Tenderizer
     * @param receiver Address of the receiver
     * @param id ID of the unlock
     * @return tokenId ID of the created token
     */
    function createUnlock(address receiver, uint256 id) external virtual isValidTenderizer(msg.sender) returns (uint256 tokenId) {
        if (id >= 1 << 96) revert InvalidID();
        tokenId = _encodeTokenId(msg.sender, uint96(id));
        _safeMint(receiver, tokenId);
    }

    /**
     * @notice Burns an unlock token
     * @dev Only callable by a Tenderizer
     * @param owner Owner of the token
     * @param id ID of the unlock
     */
    function useUnlock(address owner, uint256 id) external virtual isValidTenderizer(msg.sender) {
        if (id >= 1 << 96) revert InvalidID();
        uint256 tokenId = _encodeTokenId(msg.sender, uint96(id));
        if (ownerOf(tokenId) != owner) revert NotOwnerOf(id, ownerOf(tokenId), owner);
        _burn(tokenId);
    }

    /**
     * @notice Returns the tokenURI of an unlock token
     * @param id ID of the unlock token
     * @return tokenURI of the unlock token
     */
    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        require(_ownerOf[id] != address(0), "non-existent token");
        return renderer.json(id);
    }

    /**
     * @notice Returns the metadata of an unlock token
     * @param tokenId ID of the unlock token
     * @return metadata of the unlock token
     */
    function getMetadata(uint256 tokenId) external view returns (Metadata memory metadata) {
        (address tenderizer, uint256 id) = _decodeTokenId(tokenId);
        address asset = Tenderizer(tenderizer).asset();

        return Metadata({
            amount: Tenderizer(tenderizer).previewWithdraw(id),
            maturity: Tenderizer(tenderizer).unlockMaturity(id),
            tokenId: id,
            symbol: ERC20(asset).symbol(),
            name: ERC20(asset).name(),
            validator: Tenderizer(tenderizer).validator()
        });
    }

    function _isValidTenderizer(address sender) internal view virtual {
        if (!registry.isTenderizer(sender)) revert NotTenderizer(sender);
    }

    function _encodeTokenId(address tenderizer, uint96 id) internal pure virtual returns (uint256) {
        return uint256(bytes32(abi.encodePacked(tenderizer, id)));
    }

    function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
        return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
    }
}
