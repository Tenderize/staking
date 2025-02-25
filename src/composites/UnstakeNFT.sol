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

import { ERC721 } from "solady/tokens/ERC721.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";

import { Base64 } from "core/unlocks/Base64.sol";

import { UnstakeRequest } from "core/composites/ctToken.sol";

pragma solidity >=0.8.19;

interface GetUnstakeRequest {
    function getUnstakeRequest(uint256 id) external view returns (UnstakeRequest memory);
}

abstract contract UnstakeNFT is Initializable, UUPSUpgradeable, OwnableUpgradeable, ERC721 {
    using Strings for uint256;
    using Strings for address;

    error NotOwner(uint256 id, address caller, address owner);
    error InvalidID(uint256 id);

    uint256 lastID;
    address token;
    address minter; // ctToken

    constructor() ERC721() {
        _disableInitializers();
    }

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
    }

    function getRequest(uint256 id) public view returns (UnstakeRequest memory) {
        return GetUnstakeRequest(minter).getUnstakeRequest(id);
    }

    function mintNFT(address to) external returns (uint256 unstakeID) {
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
    function json(UnstakeRequest memory data) public view returns (string memory) {
        return string(
            abi.encodePacked(
                "data:application/json;base64,",
                Base64.encode(
                    abi.encodePacked(
                        '{"name":', symbol(), '"description":', name(), ",", '"attributes":[', _serializeMetadata(data), "]}"
                    )
                )
            )
        );
    }

    function svg(UnstakeRequest memory data) external pure returns (string memory) {
        return string(
            abi.encodePacked(
                '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
                " xmlns:xlink='http://www.w3.org/1999/xlink'>",
                Base64.encode(
                    abi.encodePacked(
                        "<rect width='290px' height='500px' fill='#",
                        "000000",
                        "'/>",
                        // "<text x='10' y='20'>",
                        // data.token.toHexString(),
                        // '</text>',
                        '><text x="10" y="40">',
                        data.amount.toString(),
                        '</text><text x="10" y="60">',
                        uint256(data.createdAt).toString(),
                        "</svg>"
                    )
                )
            )
        );
    }

    function _serializeMetadata(UnstakeRequest memory data) internal pure returns (string memory metadataString) {
        metadataString = string(
            abi.encodePacked(
                '{"trait_type": "createdAt", "value":',
                uint256(data.createdAt).toString(),
                "},",
                '{"trait_type": "amount", "value":',
                data.amount.toString(),
                "},"
            )
        );
        // '{"trait_type": "token", "value":"',
        // data.token.toHexString(),
        // '"},'
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner { }
}

// Example usage e.g. LPT
contract UnstLPT is UnstakeNFT {
    function name() public pure override returns (string memory) {
        return "Unstake LPT";
    }

    function symbol() public pure override returns (string memory) {
        return "UnstLPT";
    }
}
