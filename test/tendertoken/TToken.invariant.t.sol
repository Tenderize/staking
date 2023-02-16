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

// solhint-disable func-name-mixedcase
// solhint-disable no-empty-blocks

contract Handler is TToken, Test {
  using LibAddressSet for AddressSet;

  uint256 public ghost_mintedSum;
  uint256 public ghost_burnedSum;

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

  function name() public view override returns (string memory) {}

  function symbol() public view override returns (string memory) {}

  function mint(address to, uint256 assets) public createActor {
    ghost_mintedSum += assets;
    _mint(to, assets);
  }

  function burn(uint256 actorSeed, uint256 amount) public useActor(actorSeed) {
    amount = bound(amount, 0, balanceOf(currentActor));

    ghost_burnedSum += amount;
    vm.prank(currentActor);
    _burn(currentActor, amount);
  }
}

contract TTokenInvariants is Test {
  Handler tToken;

  function setUp() public {
    tToken = new Handler();

    bytes4[] memory selectors = new bytes4[](2);
    selectors[0] = Handler.mint.selector;
    selectors[1] = Handler.burn.selector;

    targetSelector(FuzzSelector({ addr: address(tToken), selectors: selectors }));
    targetContract(address(tToken));
  }

  function invariant_totalSupply() public {
    console2.log(tToken.ghost_burnedSum());
    assertEq(tToken.totalSupply(), tToken.ghost_mintedSum() - tToken.ghost_burnedSum());
  }
}
