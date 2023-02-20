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

contract TestTToken is TToken {
  function name() public view override returns (string memory) {}

  function symbol() public view override returns (string memory) {}

  function burn(address from, uint256 amount) public {
    _burn(from, amount);
  }

  function mint(address to, uint256 amount) public {
    _mint(to, amount);
  }
}

contract Handler is Test, TestHelpers {
  using LibAddressSet for AddressSet;

  TestTToken public ttoken;
  uint256 public ghost_mintedSum;
  uint256 public ghost_burnedSum;
  uint256 public MAX_INT_SQRT = sqrt(type(uint256).max - 1);
  uint256 public ghost_notTenderizedSupply = MAX_INT_SQRT;

  AddressSet internal _actors;
  address internal currentActor;
  mapping(bytes32 => uint256) public calls;

  constructor(TestTToken _ttoken) {
    ttoken = _ttoken;
  }

  modifier countCall(bytes32 key) {
    calls[key]++;
    _;
  }

  modifier useActor(uint256 actorIndexSeed) {
    currentActor = _actors.rand(actorIndexSeed);
    _;
  }

  function createActor() public {
    currentActor = msg.sender;
    _actors.add(msg.sender);
  }

  function callSummary() public view {
    console2.log("Call summary:");
    console2.log("-------------------");
    console2.log("mint", calls["mint"]);
    console2.log("burn", calls["burn"]);
    console2.log("transfer", calls["transfer"]);
  }

  function mint(uint256 amount) public countCall("mint") {
    if (ghost_notTenderizedSupply == 0) {
      return;
    }
    createActor();

    amount = bound(amount, 1, ghost_notTenderizedSupply);
    ghost_notTenderizedSupply -= amount;
    ghost_mintedSum += amount;
    ttoken.mint(currentActor, amount);
  }

  function transfer(
    uint256 actorSeed,
    address to,
    uint256 amount
  ) public useActor(actorSeed) countCall("transfer") {
    if (ttoken.balanceOf(currentActor) == 0) {
      return;
    }
    amount = bound(amount, 1, ttoken.balanceOf(currentActor));

    vm.startPrank(currentActor);
    ttoken.transfer(to, amount);
    vm.stopPrank();
  }

  function burn(uint256 actorSeed, uint256 amount) public useActor(actorSeed) countCall("burn") {
    if (ttoken.balanceOf(currentActor) == 0) {
      return;
    }
    amount = bound(amount, 1, ttoken.balanceOf(currentActor));

    ghost_burnedSum += amount;
    ghost_notTenderizedSupply += amount;
    ttoken.burn(currentActor, amount);
  }
}

contract TTokenInvariants is Test {
  Handler public handler;
  TestTToken public ttoken;

  function setUp() public {
    ttoken = new TestTToken();
    handler = new Handler(ttoken);

    bytes4[] memory selectors = new bytes4[](3);
    selectors[0] = Handler.mint.selector;
    selectors[1] = Handler.burn.selector;
    selectors[2] = Handler.transfer.selector;

    targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
    targetContract(address(handler));
  }

  function invariant_totalSupply() public {
    assertEq(ttoken.totalSupply(), handler.ghost_mintedSum() - handler.ghost_burnedSum());
  }

  function invariant_callSummary() public view {
    handler.callSummary();
  }
}
