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

import { Test } from "forge-std/Test.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { TestHelpers, AddressSet, LibAddressSet } from "test/helpers/Helpers.sol";

// solhint-disable func-name-mixedcase
// solhint-disable var-name-mixedcase
// solhint-disable no-empty-blocks

contract TestTToken is TToken {
    function name() public view override returns (string memory) { }

    function symbol() public view override returns (string memory) { }

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

    AddressSet internal holders;
    AddressSet internal actors;
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
        currentActor = actors.rand(actorIndexSeed);
        _;
    }

    function getHolders() public view returns (address[] memory) {
        return holders.addrs;
    }

    function createActor() public {
        currentActor = msg.sender;
        actors.add(msg.sender);
    }

    function callSummary() public view {
        console2.log("Call summary:");
        console2.log("-------------------");
        console2.log("mint", calls["mint"]);
        console2.log("burn", calls["burn"]);
        console2.log("transfer", calls["transfer"]);
        console2.log("approve", calls["approve"]);
        console2.log("transferFrom", calls["transferFrom"]);
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
        holders.add(currentActor);
    }

    function transfer(uint256 actorSeed, address to, uint256 amount) public useActor(actorSeed) countCall("transfer") {
        if (ttoken.balanceOf(currentActor) == 0) {
            return;
        }
        amount = bound(amount, 1, ttoken.balanceOf(currentActor));

        vm.startPrank(currentActor);
        ttoken.transfer(to, amount);
        holders.add(to);
        vm.stopPrank();
    }

    function approve(uint256 actorSeed, address spender, uint256 amount) public useActor(actorSeed) countCall("approve") {
        vm.startPrank(currentActor);
        ttoken.approve(spender, amount);
        vm.stopPrank();
    }

    function transferFrom(
        uint256 actorSeed,
        address from,
        address to,
        uint256 amount
    )
        public
        useActor(actorSeed)
        countCall("transferFrom")
    {
        if (ttoken.balanceOf(from) == 0) {
            return;
        }
        uint256 allowance = ttoken.allowance(from, currentActor);
        if (allowance == 0) {
            return;
        }
        amount = bound(amount, 1, allowance);

        vm.startPrank(currentActor);
        ttoken.transferFrom(from, to, amount);
        holders.add(to);
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

        bytes4[] memory selectors = new bytes4[](5);
        selectors[0] = Handler.mint.selector;
        selectors[1] = Handler.burn.selector;
        selectors[2] = Handler.transfer.selector;
        selectors[3] = Handler.approve.selector;
        selectors[4] = Handler.transferFrom.selector;

        targetSelector(FuzzSelector({ addr: address(handler), selectors: selectors }));
        targetContract(address(handler));

        // these excludes are needed because there's a bug when using contract addresses as senders
        // https://github.com/foundry-rs/foundry/issues/4163
        // https://github.com/foundry-rs/foundry/issues/3879
        excludeSender(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
        excludeSender(0x4e59b44847b379578588920cA78FbF26c0B4956C);
        excludeSender(address(ttoken));
        excludeSender(address(handler));
        excludeSender(address(this));
    }

    // total supply should equal sum of minted - sum of burned
    function invariant_mintedPlusBurnt() public {
        assertEq(ttoken.totalSupply(), handler.ghost_mintedSum() - handler.ghost_burnedSum());
    }

    // sum of holder balances should equal total supply
    function invariant_holderBalances() public {
        uint256 sum = 0;
        address[] memory holders = handler.getHolders();
        for (uint256 i = 0; i < holders.length; i++) {
            sum += ttoken.balanceOf(holders[i]);
        }
        assertEq(ttoken.totalSupply(), sum);
    }

    function invariant_callSummary() public view {
        handler.callSummary();
    }
}
