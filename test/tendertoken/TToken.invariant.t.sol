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

import "forge-std/console2.sol";

import { Test } from "forge-std/test.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { AddressSet, LibAddressSet } from "../Helpers.sol";
import { TestHelpers } from "test/helpers/Helpers.sol";

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase
// solhint-disable no-empty-blocks

contract Handler is TToken, Test, TestHelpers {
  using LibAddressSet for AddressSet;

  uint256 public ghost_mintedSum;
  uint256 public ghost_burnedSum;
  uint256 public MAX_INT_SQRT = sqrt(type(uint256).max - 1);
  uint256 public ghost_circulatingSupply = MAX_INT_SQRT;

  AddressSet internal _actors;
  address internal currentActor;

  modifier createActor() {
    currentActor = msg.sender;
    _actors.add(msg.sender);
    _;
  }

  modifier useActor(uint256 actorIndexSeed) {
    currentActor = _actors.rand(actorIndexSeed);
    _;
  }

  // mapping(bytes32 => uint256) public calls;

  // modifier countCall(bytes32 key) {
  //   calls[key]++;
  //   _;
  // }

  // function callSummary() public view {
  //   console2.log("Call summary:");
  //   console2.log("-------------------");
  //   console2.log("mint", calls["mint"]);
  //   console2.log("burn", calls["burn"]);
  // }

  function mint(uint256 amount) public {
    // vm.assume(amount != 0);
    // vm.assume(amount < ghost_underlyingSupply);
    if (ghost_circulatingSupply < 1) {
      return;
    }
    currentActor = msg.sender;
    _actors.add(msg.sender);

    amount = bound(amount, 1, ghost_circulatingSupply);
    ghost_circulatingSupply -= amount;
    ghost_mintedSum += amount;
    vm.prank(currentActor);
    _mint(currentActor, amount);
  }

  function burn(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
    if (!_actors.contains(currentActor)) {
      return;
    }
    console2.log("contains", _actors.contains(currentActor));
    console2.log("address", currentActor);
    console2.log("balanceOf", balanceOf(currentActor));
    amount = bound(amount, 1, balanceOf(currentActor));

    ghost_burnedSum += amount;
    ghost_circulatingSupply += amount;
    vm.prank(currentActor);
    _burn(currentActor, amount);
  }

  function name() public view override returns (string memory) {}

  function symbol() public view override returns (string memory) {}
}

contract TTokenInvariants is Test {
  Handler handler;

  function setUp() public {
    handler = new Handler();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = Handler.mint.selector;
    selectors[1] = Handler.burn.selector;

    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_totalSupply() public {
    console2.log(handler.ghost_burnedSum());
    assertEq(handler.totalSupply(), handler.ghost_mintedSum() - handler.ghost_burnedSum());
  }

  // function invariant_callSummary() public view {
  //   handler.callSummary();
  // }
}
