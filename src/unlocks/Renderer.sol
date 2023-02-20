// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Base64 } from "openzeppelin-contracts/utils/Base64.sol";
import { Strings } from "openzeppelin-contracts/utils/Strings.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";

// solhint-disable quotes

contract Renderer is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  using Strings for uint256;

  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  function json(uint256 id) external view returns (string memory) {
    Unlocks.Metadata memory data = Unlocks(msg.sender).getMetadata(id);

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

  function _serializeMetadata(Unlocks.Metadata memory data) internal pure returns (string memory metadataString) {
    metadataString = string(
      abi.encodePacked(
        '{"trait_type": "maturity", "value":',
        data.maturity.toString(),
        "},",
        '{"trait_type": "amount", "value":',
        data.amount.toString(),
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

  function svg(Unlocks.Metadata memory data) internal pure returns (string memory) {
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
              data.amount.toString(),
              '</text><text x="10" y="60">',
              data.maturity.toString(),
              '</text><text x="10" y="80">',
              data.tokenId.toString(),
              "</text>",
              "</svg>"
            )
          )
        )
      );
  }

  ///@dev required by the OZ UUPS module
  function _authorizeUpgrade(address) internal override onlyOwner {}
}
