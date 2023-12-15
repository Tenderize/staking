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

pragma solidity >=0.8.19;

import { Test } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";

import {
    PolygonAdapter,
    POLYGON_STAKEMANAGER,
    POL,
    WITHDRAW_DELAY,
    EXCHANGE_RATE_PRECISION_HIGH,
    _getValidatorSharesContract,
    _getValidatorId
} from "core/adapters/PolygonAdapter.sol";
import { IPolygonStakeManager, IPolygonValidatorShares } from "core/adapters/interfaces/IPolygon.sol";
import { Tenderizer, TenderizerEvents } from "core/tenderizer/Tenderizer.sol";
import { Unlocks, Metadata } from "core/unlocks/Unlocks.sol";
import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";
import { Factory } from "core/factory/Factory.sol";
import { TenderizerFixture, tenderizerFixture } from "./Fixture.sol";

address constant VALIDATOR_1 = 0xe7DB0D2384587956ef9d47304E96236022cCE3Af; // 0xeA105Ab4e3F01f7f8DA09Cb84AB501Aeb02E9FC7;
address constant TOKEN_HOLDER = 0xF977814e90dA44bFA03b6295A0616a897441aceC;
address constant GOVERNANCE = 0x6e7a5820baD6cebA8Ef5ea69c0C92EbbDAc9CE48;
uint256 constant REWARD_PRECISION = 1e25;

interface IPolygonStakeManagerTest is IPolygonStakeManager {
    function setCurrentEpoch(uint256 epoch) external;
}

interface IPolygonValidatorSharesTest is IPolygonValidatorShares {
    function initalRewardPerShare(address user) external view returns (uint256);
}

contract PolygonForkTest is Test, TenderizerEvents, ERC721Receiver {
    TenderizerFixture fixture;
    PolygonAdapter adapter;

    uint256 balance;

    event NewTenderizer(address indexed asset, address indexed validator, address tenderizer);

    function setRewards(uint256 amount, uint256 initialRewardPerShare) internal returns (uint256 rewardPerShare) {
        IPolygonValidatorShares valShares = _getValidatorSharesContract(_getValidatorId(VALIDATOR_1));
        uint256 totalShares = valShares.totalSupply();
        rewardPerShare = initialRewardPerShare + amount * REWARD_PRECISION / totalShares;
        // We have to update the `Validator.delegatorsRewards` for our validator
        // in the StakingManager contract.
        // for the current hardcoded validator this storage slot can be found at
        // '0x511480fe2fa645166a40382828f5ab06983719d0fe9ae7a53d61f4612e299e33'
        vm.store(address(POLYGON_STAKEMANAGER), 0x511480fe2fa645166a40382828f5ab06983719d0fe9ae7a53d61f4612e299e33, bytes32(amount));
    }

    function setUp() public {
        bytes32 salt = bytes32(uint256(1));
        vm.createSelectFork(vm.envString("MAINNET_RPC"));
        fixture = tenderizerFixture();
        adapter = new PolygonAdapter{ salt: salt }();
        fixture.registry.registerAdapter(address(POL), address(adapter));
        balance = POL.balanceOf(TOKEN_HOLDER);
        vm.prank(TOKEN_HOLDER);
        POL.transfer(address(this), balance);
    }

    function test_registry_AdapterRegistered() public {
        assertEq(fixture.registry.adapter(address(POL)), address(adapter), "adapter not registered");
    }

    function test_adapter_unlockTime() public {
        assertEq(adapter.unlockTime(), WITHDRAW_DELAY, "unlock time not set");
    }

    function test_currentTime() public {
        assertEq(adapter.currentTime(), POLYGON_STAKEMANAGER.epoch(), "current time not set");
    }

    function test_isValidator() public {
        assertEq(adapter.isValidator(VALIDATOR_1), true, "isValidator true incorrect");
        vm.expectRevert();
        adapter.isValidator(makeAddr("NOT VALIDATOR"));
    }

    function test_factory_newTenderizer() public {
        // Revert with inactive validator
        address inactiveValidator = makeAddr("INACTIVE_VALIDATOR");
        vm.expectRevert();
        fixture.factory.newTenderizer(address(POL), inactiveValidator);

        // Deploy tenderizer
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: false, checkData: false });
        emit NewTenderizer(address(POL), VALIDATOR_1, address(0x0));
        fixture.factory.newTenderizer(address(POL), VALIDATOR_1);
    }

    function testFuzz_previewDeposit(uint256 amount) public {
        amount = bound(amount, 1, 10e28);
        IPolygonValidatorShares valShares = _getValidatorSharesContract(_getValidatorId(VALIDATOR_1));
        uint256 totalShares = valShares.totalSupply();
        uint256 delegatedAmount = POLYGON_STAKEMANAGER.delegatedAmount(_getValidatorId(VALIDATOR_1));
        uint256 preview = adapter.previewDeposit(VALIDATOR_1, amount);
        uint256 mintedPolShares =
            amount * EXCHANGE_RATE_PRECISION_HIGH / (delegatedAmount * EXCHANGE_RATE_PRECISION_HIGH / totalShares);
        uint256 amountToTransfer =
            mintedPolShares * (delegatedAmount * EXCHANGE_RATE_PRECISION_HIGH / totalShares) / EXCHANGE_RATE_PRECISION_HIGH;

        uint256 exp = mintedPolShares
            * ((delegatedAmount + amountToTransfer) * EXCHANGE_RATE_PRECISION_HIGH / (totalShares + mintedPolShares))
            / EXCHANGE_RATE_PRECISION_HIGH;
        assertEq(preview, exp, "previewDeposit incorrect");
    }

    function testFuzz_deposit(uint256 amount) public {
        amount = bound(amount, 1, balance);

        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(POL), VALIDATOR_1)));

        IPolygonValidatorShares valShares = _getValidatorSharesContract(_getValidatorId(VALIDATOR_1));
        uint256 totalShares = valShares.totalSupply();
        uint256 delegatedAmount = POLYGON_STAKEMANAGER.delegatedAmount(_getValidatorId(VALIDATOR_1));
        uint256 preview = tenderizer.previewDeposit(amount);

        uint256 fxRateBefore = delegatedAmount * EXCHANGE_RATE_PRECISION_HIGH / totalShares;
        assertEq(fxRateBefore, valShares.exchangeRate());

        uint256 mintedPolShares = amount * EXCHANGE_RATE_PRECISION_HIGH / fxRateBefore;
        uint256 amountToTransfer = mintedPolShares * fxRateBefore / EXCHANGE_RATE_PRECISION_HIGH;
        uint256 expectedOut = mintedPolShares
            * ((delegatedAmount + amountToTransfer) * EXCHANGE_RATE_PRECISION_HIGH / (totalShares + mintedPolShares))
            / EXCHANGE_RATE_PRECISION_HIGH;
        POL.approve(address(tenderizer), amount);
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: false, checkData: true });
        emit Deposit(address(this), address(this), amount, expectedOut);
        uint256 tTokenOut = tenderizer.deposit(address(this), amount);
        assertEq(preview, tTokenOut, "previewDeposit incorrect");
        uint256 fxRateAfter = (delegatedAmount + amountToTransfer) * EXCHANGE_RATE_PRECISION_HIGH / (totalShares + mintedPolShares);
        assertEq(fxRateAfter, valShares.exchangeRate());

        assertEq(tenderizer.totalSupply(), expectedOut, "total supply incorrect");
        assertEq(tenderizer.balanceOf(address(this)), expectedOut, "balance incorrect");
    }

    function test_unlock_withdraw_simple() public {
        uint256 depositAmount = 100_000 ether;
        uint256 unstakeAmount = 25_000 ether;
        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(POL), VALIDATOR_1)));
        POL.approve(address(tenderizer), depositAmount);
        tenderizer.deposit(address(this), depositAmount);

        vm.expectEmit();
        emit Unlock(address(this), unstakeAmount, 1);
        uint256 unlockID = tenderizer.unlock(unstakeAmount);
        assertEq(unlockID, 1, "unlockID incorrect");

        assertEq(tenderizer.unlockMaturity(unlockID), POLYGON_STAKEMANAGER.epoch() + WITHDRAW_DELAY, "unlockMaturity incorrect");

        uint256 tokenId = uint256(bytes32(abi.encodePacked(address(tenderizer), uint96(unlockID))));
        Metadata memory metadata = fixture.unlocks.getMetadata(tokenId);
        assertEq(metadata.amount, unstakeAmount, "amount incorrect");
        assertEq(metadata.unlockId, unlockID, "unlockID incorrect");
        assertEq(metadata.validator, VALIDATOR_1, "validator incorrect");
        assertEq(metadata.maturity, POLYGON_STAKEMANAGER.epoch() + WITHDRAW_DELAY, "maturity incorrect");
        assertEq(metadata.progress, 0, "progress incorrect");

        // Process epochs to 50%
        uint256 newEpoch = POLYGON_STAKEMANAGER.epoch() + WITHDRAW_DELAY / 2;
        vm.prank(GOVERNANCE);
        IPolygonStakeManagerTest(address(POLYGON_STAKEMANAGER)).setCurrentEpoch(newEpoch);
        metadata = fixture.unlocks.getMetadata(tokenId);
        assertEq(metadata.progress, 50, "metadata progress incorrect");

        newEpoch = POLYGON_STAKEMANAGER.epoch() + WITHDRAW_DELAY;
        vm.prank(GOVERNANCE);
        IPolygonStakeManagerTest(address(POLYGON_STAKEMANAGER)).setCurrentEpoch(newEpoch);

        uint256 polBalBefore = POL.balanceOf(address(this));
        vm.expectEmit();
        emit Withdraw(address(this), unstakeAmount, unlockID);
        uint256 withdrawn = tenderizer.withdraw(address(this), unlockID);
        assertEq(withdrawn, unstakeAmount, "withdrawn incorrect");
        assertEq(POL.balanceOf(address(this)), polBalBefore + unstakeAmount, "balance incorrect");
        assertEq(tenderizer.totalSupply(), depositAmount - unstakeAmount, "total supply incorrect");
        vm.expectRevert("NOT_MINTED");
        fixture.unlocks.ownerOf(tokenId);
    }

    // TODO: test slash while undelegating

    // TODO: make fuzz test
    function test_rebase() public {
        uint256 rewardAmount = 100_000 ether;

        address HOLDER_1 = makeAddr("HOLDER_1");
        address HOLDER_2 = makeAddr("HOLDER_2");
        uint256 HOLDER_1_DEPOSIT = 25_000 ether;
        uint256 HOLDER_2_DEPOSIT = 12_500 ether;
        POL.transfer(HOLDER_1, HOLDER_1_DEPOSIT);
        POL.transfer(HOLDER_2, HOLDER_2_DEPOSIT);

        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(POL), VALIDATOR_1)));
        vm.startPrank(HOLDER_1);
        POL.approve(address(tenderizer), HOLDER_1_DEPOSIT);
        uint256 tTokenOut_1 = tenderizer.deposit(HOLDER_1, HOLDER_1_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(HOLDER_2);
        POL.approve(address(tenderizer), HOLDER_2_DEPOSIT);
        uint256 tTokenOut_2 = tenderizer.deposit(HOLDER_2, HOLDER_2_DEPOSIT);
        vm.stopPrank();
        IPolygonValidatorShares valShares = _getValidatorSharesContract(_getValidatorId(VALIDATOR_1));

        uint256 tenderizerValShares = valShares.balanceOf(address(tenderizer));
        uint256 initialRewardPerShare = IPolygonValidatorSharesTest(address(valShares)).initalRewardPerShare(address(tenderizer));
        uint256 rewardPerShare = setRewards(rewardAmount, initialRewardPerShare);
        // Due to logic in the Polygon contracts the actual reward amount will be rewardAmount -1
        // uint256 tenderizerRewardAfterFee = rewardsForTenderizer - rewardsForTenderizer * 5e3 / 1e6;
        uint256 tenderizerRewards = tenderizerValShares * (rewardPerShare - initialRewardPerShare) / REWARD_PRECISION;
        vm.expectEmit();
        emit Rebase(tTokenOut_1 + tTokenOut_2, tTokenOut_1 + tTokenOut_2 + tenderizerRewards);
        tenderizer.rebase();

        assertEq(
            tenderizer.totalSupply(),
            valShares.balanceOf(address(tenderizer)) * valShares.exchangeRate() / EXCHANGE_RATE_PRECISION_HIGH,
            "total supply incorrect vs total staked incorrect"
        );
        assertEq(tenderizer.totalSupply(), tTokenOut_1 + tTokenOut_2 + tenderizerRewards, "total supply incorrect");
        assertEq(
            tenderizer.balanceOf(HOLDER_1),
            tTokenOut_1 + tenderizerRewards * tTokenOut_1 / (tTokenOut_1 + tTokenOut_2),
            "balance 1 incorrect"
        );
        assertEq(
            tenderizer.balanceOf(HOLDER_2),
            tTokenOut_2 + tenderizerRewards * tTokenOut_2 / (tTokenOut_1 + tTokenOut_2),
            "balance 2 incorrect"
        );
    }
}
