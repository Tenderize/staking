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

// solhint-disable func-name-mixedcase
// solhint-disable no-empty-blocks

pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { Base64 } from "core/unlocks/Base64.sol";

contract Base64Test is Test {
    function test_Encode() public {
        string memory encoded = Base64.encode("Hello, world!");
        assertEq(encoded, "SGVsbG8sIHdvcmxkIQ==");
    }

    function test_Decode() public {
        string memory decoded = string(Base64.decode("SGVsbG8sIHdvcmxkIQ=="));
        assertEq(decoded, "Hello, world!");
    }

    function test_EncodeDecode() public {
        string memory encoded = Base64.encode("Hello, world!");
        string memory decoded = string(Base64.decode(encoded));
        assertEq(decoded, "Hello, world!");
    }
}
