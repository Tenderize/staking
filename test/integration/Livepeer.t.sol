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

// TODO: Negative paths

import { Test, stdError } from "forge-std/Test.sol";
import { TestHelpers } from "test/helpers/Helpers.sol";
import { IERC20, IERC20Metadata } from "core/interfaces/IERC20.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { TenderizerEvents } from "core/tenderizer/TenderizerBase.sol";
import { LivepeerAdapter } from "core/adapters/LivepeerAdapter.sol";
import { AdapterDelegateCall } from "core/adapters/Adapter.sol";
import { ILivepeerBondingManager, ILivepeerRoundsManager } from "core/adapters/interfaces/ILivepeer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Factory } from "core/factory/Factory.sol";
import { Renderer } from "core/unlocks/Renderer.sol";
import { Registry } from "core/registry/Registry.sol";
import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IWETH9 } from "core/adapters/interfaces/IWETH9.sol";
import { ISwapRouter } from "core/adapters/interfaces/ISwapRouter.sol";

// solhint-disable func-name-mixedcase
// solhint-disable state-visibility

contract LivepeerIntegrationTest is Test, TestHelpers, TenderizerEvents {
    using ClonesWithImmutableArgs for address;

    uint256 MAX_INT = type(uint256).max;
    uint256 MAX_INT_SQRT = sqrt(MAX_INT - 1);

    bytes32 private constant FACTORY_ROLE = keccak256("FACTORY_ROLE");

    address bondingManager = 0x35Bcf3c30594191d53231E4FF333E8A770453e40;
    address roundsManager = 0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f;
    address asset = 0x289ba1701C2F088cf0faf8B3705246331cB8A839;
    address weth = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
    address uniswap = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    Registry registry;
    LivepeerAdapter adapter;
    Renderer renderer;
    Unlocks unlocks;
    Tenderizer tenderizer;
    Factory factory;

    address account1 = vm.addr(1);
    address account2 = vm.addr(2);
    address account3 = vm.addr(3);
    address validator = vm.addr(4);
    address treasury = vm.addr(5);

    // solhint-disable-next-line const-name-snakecase
    uint256 constant depositCount = 5;
    uint256 depositAmount = 10_000 ether;
    uint256 unlockAmount = 1000 ether;
    uint256 unlockID = 1;

    function setUp() public {
        address(new Registry());
        registry = Registry(address(new ERC1967Proxy(address(new Registry()), "")));
        registry.initialize();
        adapter = new LivepeerAdapter();
        registry.registerAdapter(asset, address(adapter));

        renderer = new Renderer();
        unlocks = new Unlocks(address(registry), address(renderer));
        factory = new Factory(address(registry), address(new Tenderizer()),  address(unlocks));
        registry.grantRole(FACTORY_ROLE, address(factory));
        registry.setFee(asset, 0.005 ether);
        registry.setTreasury(treasury);

        vm.mockCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.isRegisteredTranscoder, (validator)), abi.encode(true));

        tenderizer = Tenderizer(factory.newTenderizer(asset, validator));
    }

    function test_Metadata() public {
        string memory symbol = "LPT";
        vm.mockCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()), abi.encode(symbol));

        vm.expectCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()));
        assertEq(tenderizer.name(), string(abi.encodePacked("tender", symbol, " ", validator)), "invalid name");

        vm.expectCall(asset, abi.encodeCall(IERC20Metadata.symbol, ()));
        assertEq(tenderizer.symbol(), string(abi.encodePacked("t", symbol, "_", validator)), "invalid symbol");
    }

    function test_InitialVaules() public {
        assertEq(registry.isTenderizer(address(tenderizer)), true);
        assertEq(address(tenderizer.asset()), asset, "invalid asset");
        assertEq(address(tenderizer.validator()), validator, "invalid validator");
    }

    function testFuzz_PreviewDeposit(uint256 amount) public {
        assertEq(tenderizer.previewDeposit(amount), amount);
    }

    function testFuzz_PreviewWithdraw(uint256 amount) public {
        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegatorUnbondingLock, (address(tenderizer), unlockID)),
            abi.encode(amount, 0)
        );
        assertEq(tenderizer.previewWithdraw(unlockID), amount);
    }

    function testFuzz_UnlockMaturity(uint256 withdrawRound, uint256 currentRound, uint256 currentBlock) public {
        uint256 roundLength = 6733;
        withdrawRound = bound(withdrawRound, 1, MAX_INT / roundLength);
        currentRound = bound(currentRound, 1, MAX_INT / roundLength);
        currentBlock = bound(currentBlock, roundLength * currentRound, MAX_INT - 1);
        uint256 roundStartBlock = rand(1, 1, currentBlock - roundLength + 1, currentBlock);

        vm.roll(currentBlock);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegatorUnbondingLock, (address(tenderizer), unlockID)),
            abi.encode(0, withdrawRound)
        );
        vm.mockCall(roundsManager, abi.encodeCall(ILivepeerRoundsManager.currentRound, ()), abi.encode(currentRound));
        vm.mockCall(roundsManager, abi.encodeCall(ILivepeerRoundsManager.roundLength, ()), abi.encode(roundLength));
        vm.mockCall(
            roundsManager,
            abi.encodeCall(ILivepeerRoundsManager.currentRoundStartBlock, ()),
            abi.encode(roundStartBlock)
        );

        uint256 expMaturity;
        // TODO: Create separate scenarios for each case?
        if (withdrawRound > currentRound) {
            expMaturity = roundLength * (withdrawRound - currentRound - 1) + roundLength - (currentBlock - roundStartBlock);
        }

        vm.expectCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegatorUnbondingLock, (address(tenderizer), unlockID))
        );
        vm.expectCall(roundsManager, abi.encodeCall(ILivepeerRoundsManager.currentRoundStartBlock, ()));
        vm.expectCall(roundsManager, abi.encodeCall(ILivepeerRoundsManager.currentRound, ()));
        vm.expectCall(roundsManager, abi.encodeCall(ILivepeerRoundsManager.roundLength, ()));
        assertEq(tenderizer.unlockMaturity(unlockID), expMaturity);
    }

    function testFuzz_Deposit(uint256 amountSeed) public {
        uint256[depositCount] memory amounts;
        address[depositCount] memory accounts;
        uint256 totalAmount;

        for (uint256 i = 0; i < depositCount; i++) {
            amounts[i] = rand(amountSeed, 1, 1, MAX_INT_SQRT / depositCount);
            totalAmount += amounts[i];
            accounts[i] = vm.addr(i + 1000);

            assertEq(tenderizer.balanceOf(accounts[i]), 0, "invalid initial balance");

            _depositMocks(accounts[i], amounts[i]);

            vm.expectCall(asset, abi.encodeCall(IERC20.transferFrom, (accounts[i], address(tenderizer), amounts[i])));
            vm.expectCall(asset, abi.encodeCall(IERC20.approve, (bondingManager, amounts[i])));
            vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.bond, (amounts[i], validator)));

            vm.prank(accounts[i]);
            tenderizer.deposit(accounts[i], amounts[i]);
            assertEq(tenderizer.totalSupply(), totalAmount, "invalid total supply");
        }

        // check balance of all accounts after all deposits
        for (uint256 i = 0; i < depositCount; i++) {
            assertEq(tenderizer.balanceOf(accounts[i]), amounts[i], "invalid balance");
        }
    }

    function test_Deposit_RevertsIfZeroAmount() public {
        vm.expectRevert();
        tenderizer.deposit(account1, 0);
    }

    function test_Deposit_RevertsIfAssetTransferFails() public {
        uint256 amount = 1 ether;
        vm.mockCall(
            asset, abi.encodeWithSelector(IERC20.transferFrom.selector, account1, address(tenderizer), amount), abi.encode(false)
        );
        vm.prank(account1);

        vm.expectRevert("TRANSFER_FROM_FAILED");
        tenderizer.deposit(account1, amount);
    }

    function test_Deposit_RevertsIfBondReverts() public {
      uint256 amount = 1 ether;
      string memory revertMessage = "BOND_FAILED";

      vm.mockCall(
        asset,
        abi.encodeCall(IERC20.transferFrom, (address(this), address(tenderizer), amount)),
        abi.encode(true)
      );
      vm.mockCall(asset, abi.encodeCall(IERC20.approve, (bondingManager, amount)), abi.encode(true));
      vm.mockCallRevert(bondingManager, abi.encodeCall(ILivepeerBondingManager.bond, (amount, validator)), abi.encode(revertMessage));

      vm.expectRevert();
      tenderizer.deposit(account1, amount);
    }

    function testFuzz_Unlock(uint256 amount) public {
        amount = bound(amount, 1, depositAmount);

        _unlockPreReq(account1, depositAmount, amount);

        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.getDelegator, (address(tenderizer))));
        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.unbond, (amount)));
        vm.expectEmit(true, true, true, true);
        emit Unlock(account1, amount, unlockID);
        vm.prank(account1);
        uint256 returnedUnlockID = tenderizer.unlock(amount);

        assertEq(returnedUnlockID, unlockID, "invalid return value");
        assertEq(tenderizer.balanceOf(account1), depositAmount - amount, "burn failed");

        assertEq(unlocks.balanceOf(account1), 1, "invalid tenderlock balance");
        assertEq(
            unlocks.ownerOf(uint256(bytes32(abi.encodePacked(address(tenderizer), uint96(unlockID))))),
            account1,
            "invalid tenderlock owner"
        );
    }

    function test_Unlock_RevertsIfUnbondFails() public {
        _unlockPreReq(account1, depositAmount, unlockAmount);
        vm.mockCallRevert(bondingManager, abi.encodeCall(ILivepeerBondingManager.unbond, (unlockAmount)), abi.encode("UNBOND_FAILED"));
        vm.prank(account1);
        vm.expectRevert();
        tenderizer.unlock(unlockAmount);
    }

    function testFuzz_Withdraw(uint256 withdrawAmount) public {
        withdrawAmount = bound(withdrawAmount, 1, unlockAmount);

        uint256 unlockID = _withdrawPreReq(account1, depositAmount, unlockAmount, withdrawAmount);

        // transfer unlock NFT to account2
        vm.prank(account1);
        unlocks.transferFrom(account1, account2, uint256(bytes32(abi.encodePacked(address(tenderizer), uint96(unlockID)))));

        vm.expectCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegatorUnbondingLock, (address(tenderizer), unlockID))
        );
        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.withdrawStake, (unlockID)));
        vm.expectCall(asset, abi.encodeCall(IERC20.transfer, (account3, withdrawAmount)));

        vm.expectEmit(true, true, true, true);
        emit Withdraw(account3, withdrawAmount, unlockID);
        vm.prank(account2);
        uint256 amountRturned = tenderizer.withdraw(account3, unlockID);

        assertEq(amountRturned, withdrawAmount, "invalid return value");
        assertEq(unlocks.balanceOf(account2), 0, "invalid tenderlock balance");

        vm.expectRevert("NOT_MINTED");
        unlocks.ownerOf(uint256(bytes32(abi.encodePacked(address(tenderizer), uint96(unlockID)))));
    }

    function test_Withdraw_RevertIfUnlockNFTNotOwnded() public {
        uint256 unlockID = _withdrawPreReq(account1, depositAmount, unlockAmount, unlockAmount);

        // transfer unlock NFT to account2
        vm.prank(account1);
        unlocks.transferFrom(account1, account2, uint256(bytes32(abi.encodePacked(address(tenderizer), uint96(unlockID)))));

        vm.prank(account1);
        vm.expectRevert(abi.encodeWithSelector(Unlocks.NotOwnerOf.selector, unlockID, account2, account1));
        tenderizer.withdraw(account2, unlockID);
    }

    function test_Withdraw_RevertIfUnderlyingWithdrawFails() public {
        uint256 unlockID = _withdrawPreReq(account1, depositAmount, unlockAmount, unlockAmount);
        vm.mockCallRevert(bondingManager, abi.encodeCall(ILivepeerBondingManager.withdrawStake, (unlockID)), abi.encode("WITHDRAW_FAILED"));
        vm.prank(account1);
        vm.expectRevert();
        tenderizer.withdraw(account1, unlockID);
    }

    function testFuzz_Rebase_PositiveWithoutFees(uint256 increase) public {
        // increase can atmost double the deposited stake
        // if increase >>> deposit, larger errors in share calculations occur
        increase = bound(increase, 1, depositAmount);
        _depositMocks(account1, depositAmount);
        vm.prank(account1);
        tenderizer.deposit(account1, depositAmount);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingFees,( address(tenderizer), 0)),
            abi.encode(0)
        );
        vm.mockCall(asset, abi.encodeCall(IERC20.balanceOf, (address(tenderizer))), abi.encode(0));
        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingStake, (address(tenderizer), 0)),
            abi.encode(depositAmount + increase)
        );

        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.pendingStake, (address(tenderizer), 0)));
        vm.expectEmit(true, true, true, true);
        emit Rebase(depositAmount, depositAmount + increase);
        tenderizer.rebase();

        // allow error of 1, for when fees = 1, and convertToShares(1) = 0
        assertLt(absDiff(tenderizer.totalSupply(), depositAmount + increase), 2, "invalid total supply");
        uint256 expFees = increase * 0.005 ether / 1 ether;
        // also account for error in share calculations
        assertLt(absDiff(tenderizer.balanceOf(account1), depositAmount + increase - expFees), 3, "invalid balance");
        assertLt(absDiff(tenderizer.balanceOf(treasury), expFees), 3, "invalid fees minted");
    }

    function testFuzz_Rebase_PositiveWithFees(uint256 increase, uint256 ethFees) public {
        uint256 ethToLpt = 283;
        // if increase or ethFees * ethToLpt >>> deposit, larger errors in share calculations occur
        increase = bound(increase, 1, depositAmount);
        ethFees = bound(ethFees, 1, 10 ether);

        _depositMocks(account1, depositAmount);
        vm.prank(account1);
        tenderizer.deposit(account1, depositAmount);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingFees, (address(tenderizer), 0)),
            abi.encode(ethFees)
        );
        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.withdrawFees, (payable(address(tenderizer)), ethFees)),
            abi.encode()
        );
        vm.deal(address(tenderizer), ethFees);
        vm.mockCall(weth, abi.encodeCall(IWETH9.deposit, ()), abi.encode());
        ISwapRouter.ExactInputSingleParams memory swapParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: weth,
            tokenOut: asset,
            fee: 10_000,
            recipient: address(tenderizer),
            deadline: block.timestamp,
            amountIn: ethFees,
            amountOutMinimum: 0,
            sqrtPriceLimitX96: 0
        });
        uint256 swappedLPT = ethFees * ethToLpt;
        vm.mockCall(uniswap, abi.encodeCall(ISwapRouter.exactInputSingle, (swapParams)), abi.encode(swappedLPT));
        swapParams.amountOutMinimum = swappedLPT;
        vm.mockCall(uniswap, abi.encodeCall(ISwapRouter.exactInputSingle, (swapParams)), abi.encode(swappedLPT));
        vm.mockCall(asset, abi.encodeCall(IERC20.balanceOf, (address(tenderizer))), abi.encode(swappedLPT));
        vm.mockCall(asset, abi.encodeCall(IERC20.approve, (address(bondingManager), swappedLPT)), abi.encode(true));
        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingStake, (address(tenderizer), 0)),
            abi.encode(depositAmount + swappedLPT + increase)
        );

        vm.expectCall(weth, abi.encodeCall(IWETH9.deposit, ()));
        vm.expectCall(uniswap, abi.encodeCall(ISwapRouter.exactInputSingle, swapParams));
        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.bond, (swappedLPT, validator)));

        vm.expectEmit(true, true, true, true);
        emit Rebase(depositAmount, depositAmount + swappedLPT + increase);
        tenderizer.rebase();

        // allow error of 1, for when fees = 1, and convertToShares(1) = 0
        assertLt(absDiff(tenderizer.totalSupply(), depositAmount + swappedLPT + increase), 2, "invalid total supply");
        uint256 expFees = (swappedLPT + increase) * 0.005 ether / 1 ether;
        // also account for error in share calculations
        assertLt(absDiff(tenderizer.balanceOf(account1), depositAmount + swappedLPT + increase - expFees), 5, "invalid balance");
        assertLt(absDiff(tenderizer.balanceOf(treasury), expFees), 5, "invalid fees minted");
    }

    function testFuzz_Rebase_Negative(uint256 slash) public {
        slash = bound(slash, 1, depositAmount);

        _depositMocks(account1, depositAmount);
        vm.prank(account1);
        tenderizer.deposit(account1, depositAmount);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingFees, (address(tenderizer), 0)),
            abi.encode(0)
        );
        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.pendingStake, (address(tenderizer), 0)),
            abi.encode(depositAmount - slash)
        );
        vm.mockCall(asset, abi.encodeCall(IERC20.balanceOf, address(tenderizer)), abi.encode(0));

        vm.expectCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.pendingStake, (address(tenderizer), 0)));
        vm.expectEmit(true, true, true, true);
        emit Rebase(depositAmount, depositAmount - slash);
        tenderizer.rebase();

        assertEq(tenderizer.totalSupply(), depositAmount - slash, "invalid total supply");
        assertEq(tenderizer.balanceOf(account1), depositAmount - slash, "invalid balance");
    }

    function _depositMocks(address account, uint256 amount) internal {
        vm.mockCall(
            asset, abi.encodeCall(IERC20.transferFrom, (account, address(tenderizer), amount)), abi.encode(true)
        );
        vm.mockCall(asset, abi.encodeCall(IERC20.approve, (bondingManager, amount)), abi.encode(true));
        vm.mockCall(bondingManager, abi.encodeCall(ILivepeerBondingManager.bond, (amount, validator)), abi.encode());
    }

    function _unlockPreReq(address account, uint256 depositAmount, uint256 unlockAmount) internal {
        _depositMocks(account, depositAmount);
        vm.prank(account);
        tenderizer.deposit(account, depositAmount);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegator, (address(tenderizer))),
            abi.encode(0, 0, 0, 0, 0, 0, unlockID)
        );
    }

    function _withdrawPreReq(
        address account,
        uint256 depositAmount,
        uint256 unlockAmount,
        uint256 withdrawAmount
    )
        internal
        returns (uint256 unlockID)
    {
        _unlockPreReq(account1, depositAmount, unlockAmount);

        vm.prank(account);
        unlockID = tenderizer.unlock(unlockAmount);

        vm.mockCall(
            bondingManager,
            abi.encodeCall(ILivepeerBondingManager.getDelegatorUnbondingLock, (address(tenderizer), unlockID)),
            abi.encode(withdrawAmount, 0)
        );
    }

    function _rebasePreReq() internal {
        _depositMocks(account1, depositAmount);
        vm.prank(account1);
        tenderizer.deposit(account1, depositAmount);

        _depositMocks(account2, depositAmount);
        vm.prank(account2);
        tenderizer.deposit(account2, depositAmount);
    }
}
