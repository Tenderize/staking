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

import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Router } from "core/router/Router.sol";

pragma solidity 0.8.17;

// TODO: add tokenURI

contract Unlocks is ERC721 {
  Router private immutable router;

  error NotOwnerOf(uint256 id, address owner, address sender);
  error NotTenderizer(address sender);

  modifier isValidTenderizer(address sender) {
    _isValidTenderizer(sender);
    _;
  }

  constructor(address _router) ERC721("Tenderize Unlocks", "TUNL") {
    router = Router(_router);
  }

  function createUnlock(
    address receiver,
    uint256 id
  ) public virtual isValidTenderizer(msg.sender) returns (uint256 tokenId) {
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
    // return all parameters DYNAMICALLY (as SVG)
    // - _getTenderizer
    // - _getValidator
    // - _getAsset
    // - _getAmount
    // - _getMaturity
    return "";
  }

  function _getTenderizer(uint256 tokenId) internal view virtual returns (address) {
    (address tenderizer, ) = _decodeTokenId(tokenId);
    return tenderizer;
  }

  function _getAmount(uint256 tokenId) internal view virtual returns (uint256) {
    (address tenderizer, uint256 id) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).previewWithdraw(id);
  }

  function _getMaturity(uint256 tokenId) internal view virtual returns (uint256) {
    (address tenderizer, uint256 id) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).unlockMaturity(id);
  }

  function _getValidator(uint256 tokenId) internal view virtual returns (address) {
    (address tenderizer, ) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).validator();
  }

  function _getAsset(uint256 tokenId) internal view virtual returns (address) {
    (address tenderizer, ) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).asset();
  }

  function _isValidTenderizer(address sender) internal view virtual {
    if (router.isTenderizer(sender)) revert NotTenderizer(sender);
  }

  function _encodeTokenId(address tenderizer, uint96 id) internal pure virtual returns (uint256) {
    return uint256(bytes32(abi.encodePacked(tenderizer, id)));
  }

  function _decodeTokenId(uint256 tokenId) internal pure virtual returns (address tenderizer, uint96 id) {
    return (address(bytes20(bytes32(tokenId))), uint96(bytes12(bytes32(tokenId) << 160)));
  }
}
