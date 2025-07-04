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

pragma solidity ^0.8.25;

import { ERC721 } from "solady/tokens/ERC721.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";

import { Base64 } from "core/unlocks/Base64.sol";

import { MultiValidatorLSTNative } from "core/tenderize-v3/multi-validator/MultiValidatorLST.sol";

interface GetUnstakeRequest {
    function getUnstakeRequest(uint256 id) external view returns (MultiValidatorLSTNative.UnstakeRequest memory);
}

contract UnstakeNFT is Initializable, UUPSUpgradeable, OwnableUpgradeable, ERC721 {
    using Strings for uint256;
    using Strings for address;

    error NotOwner(uint256 id, address caller, address owner);
    error NotMinter(address caller);
    error InvalidID(uint256 id);

    uint256 lastID;
    string public tokenSymbol; // Symbol of the native token (e.g., "ETH", "SEI")
    address minter; // MultiValidatorLSTNative contract

    constructor() ERC721() {
        _disableInitializers();
    }

    modifier onlyMinter() {
        if (msg.sender != minter) {
            revert NotMinter(msg.sender);
        }
        _;
    }

    function name() public view override returns (string memory) {
        return string.concat("Unstaking ", tokenSymbol);
    }

    function symbol() public view override returns (string memory) {
        return string.concat("Unst", tokenSymbol);
    }

    function initialize(string memory _tokenSymbol, address _minter) external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        tokenSymbol = _tokenSymbol;
        minter = _minter;
    }

    function getRequest(uint256 id) public view returns (MultiValidatorLSTNative.UnstakeRequest memory) {
        return GetUnstakeRequest(minter).getUnstakeRequest(id);
    }

    function mintNFT(address to) external onlyMinter returns (uint256 unstakeID) {
        unstakeID = ++lastID;
        _safeMint(to, unstakeID);
    }

    function burnNFT(address from, uint256 id) external {
        if (ownerOf(id) != from) {
            revert NotOwner(id, msg.sender, from);
        }
        _burn(id);
    }

    function setMinter(address _minter) external onlyOwner {
        minter = _minter;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        if (ownerOf(tokenId) == address(0)) {
            revert InvalidID(tokenId);
        }
        return json(getRequest(tokenId));
    }

    /**
     * @notice Returns the JSON metadata for a given unlock
     * @param data metadata for the token
     */
    function json(MultiValidatorLSTNative.UnstakeRequest memory data) public view returns (string memory) {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":"', name(), '","description":"', name(), '",', '"attributes":[', _serializeMetadata(data), "]}"
                    )
                )
            )
        );
    }

    function svg(MultiValidatorLSTNative.UnstakeRequest memory data) external view returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                "<rect width='290px' height='500px' fill='#000000'/>",
                "<text x='10' y='40' fill='white' font-family='Arial' font-size='14'>Amount: ",
                data.amount.toString(),
                "</text>",
                "<text x='10' y='60' fill='white' font-family='Arial' font-size='14'>Created: ",
                uint256(data.createdAt).toString(),
                "</text>",
                "<text x='10' y='80' fill='white' font-family='Arial' font-size='14'>Validators: ",
                data.tenderizers.length.toString(),
                "</text>",
                "</svg>"
            )
        );
    }

    function _serializeMetadata(MultiValidatorLSTNative.UnstakeRequest memory data)
        internal
        pure
        returns (string memory metadataString)
    {
        metadataString = string(
            abi.encodePacked(
                '{"trait_type": "createdAt", "value":',
                uint256(data.createdAt).toString(),
                "},",
                '{"trait_type": "amount", "value":',
                data.amount.toString(),
                "},",
                '{"trait_type": "validators", "value":',
                data.tenderizers.length.toString(),
                "}"
            )
        );
    }

    ///@dev required by the OZ UUPS module
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
