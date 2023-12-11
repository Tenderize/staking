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

// solhint-disable state-visibility
// solhint-disable func-name-mixedcase

pragma solidity >=0.8.19;

import { Test, stdError } from "forge-std/Test.sol";
import { PolygonAdapter, EXCHANGE_RATE_PRECISION_HIGH, WITHDRAW_DELAY } from "core/adapters/PolygonAdapter.sol";
import { ITenderizer } from "core/tenderizer/ITenderizer.sol";
import { IMaticStakeManager, IValidatorShares, DelegatorUnbond } from "core/adapters/interfaces/IPolygon.sol";
import { AdapterDelegateCall } from "core/adapters/Adapter.sol";

contract PolygonAdapterTest is Test {
    using AdapterDelegateCall for PolygonAdapter;

    address MATIC_STAKE_MANAGER = 0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908;
    address validatorShares = vm.addr(1);
    uint256 validatorId = 8;

    PolygonAdapter adapter;

    function setUp() public {
        adapter = new PolygonAdapter();
        vm.etch(MATIC_STAKE_MANAGER, bytes("code"));

        // Set default mock calls
        // set validator to `address(this)`
        vm.mockCall(address(this), abi.encodeCall(ITenderizer.validator, ()), abi.encode(address(this)));
        // set validator id for `address(this)` to 8 (not a foundation validator)
        vm.mockCall(
            MATIC_STAKE_MANAGER, abi.encodeCall(IMaticStakeManager.getValidatorId, (address(this))), abi.encode(validatorId)
        );
        // set validator shares contract for `address(this)` to `validatorShares`
        vm.mockCall(
            MATIC_STAKE_MANAGER, abi.encodeCall(IMaticStakeManager.getValidatorContract, (validatorId)), abi.encode(validatorShares)
        );
    }

    function test_isValidator() public {
        assertTrue(adapter.isValidator(address(this)));
    }

    function test_previewDeposit() public {
        uint256 assets = 100;
        uint256 expected = assets;
        uint256 actual = adapter.previewDeposit(validatorShares, assets);
        assertEq(actual, expected);
    }

    function testFuzz_previewWithdraw(uint256 shares, uint256 fxRate) public {
        fxRate = bound(fxRate, 0.1 ether, 100 ether);
        shares = bound(shares, 1 ether, type(uint256).max / fxRate);
        uint256 unlockID = 1;
        uint256 expected = shares * fxRate / EXCHANGE_RATE_PRECISION_HIGH;

        DelegatorUnbond memory unbond = DelegatorUnbond({ shares: shares, withdrawEpoch: 0 });

        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.unbonds_new, (address(this), unlockID)), abi.encode(unbond));
        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.withdrawExchangeRate, ()), abi.encode(fxRate));
        uint256 actual = abi.decode(adapter._delegatecall(abi.encodeCall(PolygonAdapter.previewWithdraw, (unlockID))), (uint256));
        assertEq(actual, expected);
    }

    function testFuzz_unlockMaturity(uint256 epoch) public {
        vm.assume(epoch <= type(uint256).max - WITHDRAW_DELAY);
        uint256 unlockID = 1;
        DelegatorUnbond memory unbond = DelegatorUnbond({ shares: 0, withdrawEpoch: epoch });

        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.unbonds_new, (address(this), unlockID)), abi.encode(unbond));
        uint256 actual = abi.decode(adapter._delegatecall(abi.encodeCall(PolygonAdapter.unlockMaturity, (unlockID))), (uint256));
        assertEq(actual, epoch + WITHDRAW_DELAY);
    }

    function test_rebase() public {
        uint256 currentStake = 100;
        uint256 newStake = 200;
        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.exchangeRate, ()), abi.encode(EXCHANGE_RATE_PRECISION_HIGH));
        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.balanceOf, (address(this))), abi.encode(newStake));
        vm.mockCallRevert(validatorShares, abi.encodeCall(IValidatorShares.restake, ()), "");
        uint256 actual =
            abi.decode(adapter._delegatecall(abi.encodeCall(PolygonAdapter.rebase, (address(this), currentStake))), (uint256));
        assertEq(actual, currentStake);

        vm.mockCall(validatorShares, abi.encodeCall(IValidatorShares.restake, ()), abi.encode(true));
        actual = abi.decode(adapter._delegatecall(abi.encodeCall(PolygonAdapter.rebase, (address(this), currentStake))), (uint256));
        assertEq(actual, newStake);
    }
}
