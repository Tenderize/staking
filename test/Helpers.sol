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

pragma solidity 0.8.17;

contract TestHelpers {
  function sqrt(uint256 a) public pure returns (uint256) {
    uint256 x = a;
    uint256 y = (a + 1) / 2;
    while (x > y) {
      x = y;
      y = (x + a / x) / 2;
    }
    return x;
  }

  function rand(
    uint256 seed,
    uint256 nonce,
    uint256 lowerBound,
    uint256 upperBound
  ) public pure returns (uint256) {
    uint256 r = (uint256(keccak256(abi.encodePacked(seed, nonce))) % (upperBound - lowerBound)) + lowerBound;
    return r;
  }
}

struct AddressSet {
  address[] addrs;
  mapping(address => bool) saved;
}

library LibAddressSet {
  function add(AddressSet storage s, address addr) internal {
    if (!s.saved[addr]) {
      s.addrs.push(addr);
      s.saved[addr] = true;
    }
  }

  function contains(AddressSet storage s, address addr) internal view returns (bool) {
    return s.saved[addr];
  }

  function count(AddressSet storage s) internal view returns (uint256) {
    return s.addrs.length;
  }

  function rand(AddressSet storage s, uint256 seed) internal view returns (address) {
    if (s.addrs.length > 0) {
      return s.addrs[seed % s.addrs.length];
    } else {
      return address(0);
    }
  }

  function forEach(AddressSet storage s, function(address) external func) internal {
    for (uint256 i; i < s.addrs.length; ++i) {
      func(s.addrs[i]);
    }
  }

  function reduce(
    AddressSet storage s,
    uint256 acc,
    function(uint256, address) external returns (uint256) func
  ) internal returns (uint256) {
    for (uint256 i; i < s.addrs.length; ++i) {
      acc = func(acc, s.addrs[i]);
    }
    return acc;
  }
}
