// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import { Base64 } from "core/unlocks/Base64.sol";

// solhint-disable quotes

library Renderer {
  function svg(
    string memory symbol,
    uint256 amount,
    uint256 maturity,
    uint256 tokenId
  ) internal pure returns (string memory) {
    return
      string(
        abi.encodePacked(
          '<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg"',
          " xmlns:xlink='http://www.w3.org/1999/xlink'>",
          Base64.encode(
            bytes(
              abi.encodePacked(
                "<rect width='290px' height='500px' fill='#",
                "000000",
                "'/>",
                "<text x='10' y='20'>",
                symbol,
                '</text><text x="10" y="40">',
                toString(amount),
                '</text><text x="10" y="60">',
                toString(maturity),
                '</text><text x="10" y="80">',
                toString(tokenId),
                "</text>",
                "</svg>"
              )
            )
          )
        )
      );
  }

  function toString(uint256 value) internal pure returns (string memory) {
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
