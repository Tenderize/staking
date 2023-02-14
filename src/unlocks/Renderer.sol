// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Base64 } from "openzeppelin-contracts/utils/Base64.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";

// solhint-disable quotes

contract Renderer is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  struct Data {
    uint256 amount;
    uint256 maturity;
    uint256 tokenId;
    string symbol;
    string name;
    string underlyingSymbol;
    string underlyingName;
  }

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  function json(Data memory data) external pure returns (string memory) {
    return
      string(
        abi.encodePacked(
          "data:application/json;base64,",
          Base64.encode(
            abi.encodePacked(
              '{"name": "TenderLock',
              // solhint-disable-next-line max-line-length
              '", "description": "TenderLock from https://tenderize.me represents ERC20 tokens during the unbonding period, thus making them tradable. Owning a TenderLock token makes the owner eligible to claim the tokens at the end of the unbonding period.", "image": "data:image/svg+xml;base64,',
              svg(data),
              '",',
              '"attributes":[',
              _serializeMetadata(data),
              "]}"
            )
          )
        )
      );
  }

  function _serializeMetadata(Data memory data) internal pure returns (string memory metadataString) {
    metadataString = string(
      abi.encodePacked(
        '{"trait_type": "maturity", "value":',
        _toString(data.maturity),
        "},",
        '{"trait_type": "amount", "value":',
        _toString(data.amount),
        "},",
        '{"trait_type": "underlyingToken", "value":"',
        data.underlyingName,
        '"},',
        '{"trait_type": "underlyingSymbol", "value":"',
        data.underlyingSymbol,
        '"},',
        '{"trait_type": "token", "value":"',
        data.name,
        '"},',
        '{"trait_type": "symbol", "value":"',
        data.symbol,
        '"}'
      )
    );
  }

  function svg(Data memory data) internal pure returns (string memory) {
    return
      string(
        abi.encodePacked(
          '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
          " xmlns:xlink='http://www.w3.org/1999/xlink'>",
          Base64.encode(
            abi.encodePacked(
              "<rect width='290px' height='500px' fill='#",
              "000000",
              "'/>",
              "<text x='10' y='20'>",
              data.symbol,
              '</text><text x="10" y="40">',
              _toString(data.amount),
              '</text><text x="10" y="60">',
              _toString(data.maturity),
              '</text><text x="10" y="80">',
              _toString(data.tokenId),
              "</text>",
              "</svg>"
            )
          )
        )
      );
  }

  ///@dev required by the OZ UUPS module
  function _authorizeUpgrade(address) internal override onlyOwner {}

  function _toString(uint256 value) internal pure returns (string memory) {
    // Inspired by OraclizeAPI's implementation - MIT licence
    // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

    if (value == 0) {
      return "0";
    }
    uint256 temp = value;
    uint256 digits;
    while (temp != 0) {
      digits++;
      temp /= 10;
    }
    bytes memory buffer = new bytes(digits);
    while (value != 0) {
      digits -= 1;
      buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
      value /= 10;
    }
    return string(buffer);
  }
}
