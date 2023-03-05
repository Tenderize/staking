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
import { Router } from "core/router/Router.sol";
import { Renderer } from "core/unlocks/Renderer.sol";

pragma solidity 0.8.17;

// solhint-disable quotes

contract Unlocks is ERC721 {
    struct Metadata {
        uint256 amount;
        uint256 maturity;
        uint256 tokenId;
        string symbol;
        string name;
        address validator;
    }

    Router private immutable router;
    Renderer private immutable renderer;

    error NotOwnerOf(uint256 id, address owner, address sender);
    error NotTenderizer(address sender);

    modifier isValidTenderizer(address sender) {
        _isValidTenderizer(sender);
        _;
    }

    constructor(address _router, address _renderer) ERC721("Tenderize Unlocks", "TUNL") {
        router = Router(_router);
        renderer = Renderer(_renderer);
    }

    function createUnlock(address receiver, uint256 id) public virtual isValidTenderizer(msg.sender) returns (uint256 tokenId) {
        require(id < 1 << 96);
        tokenId = _encodeTokenId(msg.sender, uint96(id));
        _safeMint(receiver, tokenId);
    }

    function useUnlock(address owner, uint256 id) public virtual isValidTenderizer(msg.sender) {
        require(id < 1 << 96);
        uint256 tokenId = _encodeTokenId(msg.sender, uint96(id));
        if (ownerOf(tokenId) != owner) revert NotOwnerOf(id, ownerOf(tokenId), owner);
        _burn(tokenId);
    }

    function tokenURI(uint256 id) public view virtual override returns (string memory) {
        require(_ownerOf[id] != address(0), "non-existent token");
        return renderer.json(id);
    }

    function getMetadata(uint256 tokenId) public view returns (Metadata memory metadata) {
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
        if (!router.isTenderizer(sender)) revert NotTenderizer(sender);
    }

    function _encodeTokenId(address tenderizer, uint96 id) internal pure virtual returns (uint256) {
        return uint256(bytes32(abi.encodePacked(tenderizer, id)));
    }

    function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
        return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
    }
}
