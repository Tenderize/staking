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
import { Base64 } from "core/unlocks/Base64.sol";
import { Renderer } from "core/unlocks/Renderer.sol";

pragma solidity 0.8.17;

// solhint-disable quotes

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

  function createUnlock(address receiver, uint256 id)
    public
    virtual
    isValidTenderizer(msg.sender)
    returns (uint256 tokenId)
  {
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
    require(ownerOf(id) != address(0));
    return
      string(
        abi.encodePacked(
          "data:application/json;base64,",
          Base64.encode(
            bytes(
              abi.encodePacked(
                '{"name": "TenderLock #',
                Renderer.toString(id),
                // solhint-disable-next-line max-line-length
                '", "description": "TenderLock from https://tenderize.me represents ERC20 tokens during the unbonding period, thus making them tradable. Owning a TenderLock token makes the owner eligible to claim the tokens at the end of the unbonding period.", "image": "data:image/svg+xml;base64,',
                Renderer.svg(_getSymbol(id), _getAmount(id), _getMaturity(id), id),
                '",',
                '"attributes":[',
                _serializeMetadata(id),
                "]}"
              )
            )
          )
        )
      );
  }

  function _serializeMetadata(uint256 id) internal view returns (string memory metadataString) {
    address asset = _getAsset(id);
    metadataString = string(
      abi.encodePacked(
        '{"trait_type": "maturity", "value":',
        Renderer.toString(_getMaturity(id)),
        "},",
        '{"trait_type": "amount", "value":',
        Renderer.toString(_getAmount(id)),
        "},",
        '{"trait_type": "underlyingToken", "value":"',
        ERC20(asset).name(),
        '"},',
        '{"trait_type": "underlyingSymbol", "value":"',
        ERC20(asset).symbol(),
        '"},',
        '{"trait_type": "token", "value":"',
        _getName(id),
        '"},',
        '{"trait_type": "symbol", "value":"',
        _getSymbol(id),
        '"}'
      )
    );
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

  function _getName(uint256 tokenId) internal view virtual returns (string memory) {
    (address tenderizer, ) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).name();
  }

  function _getSymbol(uint256 tokenId) internal view virtual returns (string memory) {
    (address tenderizer, ) = _decodeTokenId(tokenId);

    return Tenderizer(tenderizer).symbol();
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
