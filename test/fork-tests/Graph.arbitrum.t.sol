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
    GraphAdapter,
    IGraphStaking,
    IGraphEpochManager,
    GRT,
    GRAPH_EPOCHS,
    GRAPH_STAKING,
    MAX_PPM
} from "core/adapters/GraphAdapter.sol";
import { Tenderizer, TenderizerEvents } from "core/tenderizer/Tenderizer.sol";
import { Unlocks, Metadata } from "core/unlocks/Unlocks.sol";
import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";
import { Factory } from "core/factory/Factory.sol";
import { TenderizerFixture, tenderizerFixture } from "./Fixture.sol";

address constant INDEXER_1 = 0x4e5c87772C29381bCaBC58C3f182B6633B5a274a;
address constant GOVERNOR = 0x8C6de8F8D562f3382417340A6994601eE08D3809;
address constant CURATION = 0x22d78fb4bc72e191C765807f8891B5e1785C8014;

interface IGraphStakingTest is IGraphStaking {
    function stake(uint256 amount) external;
    function allocate(
        bytes32 _subgraphDeploymentID,
        uint256 _tokens,
        address _allocationID,
        bytes32 _metadata,
        bytes calldata _proof
    )
        external;
    function closeAllocation(address _allocationID, bytes32 _poi) external;
}

interface IGraphEpochsTest is IGraphEpochManager {
    function epochLength() external view returns (uint256);
    function currentEpochBlocksSinceStart() external view returns (uint256);
}

interface IGraphCurationTest {
    function mint(bytes32 _subgraphDeploymentID, uint256 _tokensIn, uint256 _signalOutMin) external returns (uint256, uint256);
}

contract GraphForkTest is Test, TenderizerEvents, ERC721Receiver {
    TenderizerFixture fixture;
    GraphAdapter adapter;
    address immutable MINTER_ROLE = makeAddr("MINTER_ROLE");

    event NewTenderizer(address indexed asset, address indexed validator, address tenderizer);

    function mintGRT(address to, uint256 amount) public {
        vm.prank(MINTER_ROLE);
        MockERC20(address(GRT)).mint(to, amount);
    }

    function setUp() public {
        bytes32 salt = bytes32(uint256(1));
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"));
        fixture = tenderizerFixture();
        adapter = new GraphAdapter{ salt: salt }();
        fixture.registry.registerAdapter(address(GRT), address(adapter));

        // Add MINTER_ROLE
        vm.prank(GOVERNOR);
        // solhint-disable-next-line avoid-low-level-calls
        (bool success,) = address(GRT).call(abi.encodeWithSignature("addMinter(address)", (address(MINTER_ROLE))));
        assertTrue(success, "assigning minter role failed");
    }

    function test_registry_AdapterRegistered() public {
        assertEq(fixture.registry.adapter(address(GRT)), address(adapter), "adapter not registered");
    }

    function test_adapter_unlockTime() public {
        assertEq(adapter.unlockTime(), 201_600, "unlock time not set");
    }

    function test_currentTime() public {
        assertEq(adapter.currentTime(), block.number, "current time not set");
    }

    function test_isValidator() public {
        assertEq(adapter.isValidator(INDEXER_1), true, "isValidator true incorrect");
        assertEq(adapter.isValidator(makeAddr("NOT_INDEXER")), false, "isValidator false incorrect");
    }

    function testFuzz_previewDeposit(uint256 amount) public {
        amount = bound(amount, 1, 10e28);
        uint256 preview = adapter.previewDeposit(INDEXER_1, amount);

        uint256 delTax = GRAPH_STAKING.delegationTaxPercentage();
        amount -= amount * delTax / MAX_PPM;
        IGraphStaking.DelegationPool memory delPool = GRAPH_STAKING.delegationPools(INDEXER_1);
        uint256 shares = delPool.tokens != 0 ? amount * delPool.shares / delPool.tokens : amount;
        uint256 expected = shares * (delPool.tokens + amount) / (delPool.shares + shares);
        assertEq(preview, expected, "previewDeposit incorrect");
    }

    function test_factory_newTenderizer() public {
        // Revert with inactive indexer
        address inactiveIndexer = makeAddr("INACTIVE_INDEXER");
        vm.expectRevert(abi.encodeWithSelector(Factory.NotValidator.selector, (inactiveIndexer)));
        fixture.factory.newTenderizer(address(GRT), inactiveIndexer);

        // Deploy tenderizer
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: false, checkData: false });
        emit NewTenderizer(address(GRT), INDEXER_1, address(0x0));
        fixture.factory.newTenderizer(address(GRT), INDEXER_1);
    }

    function test_deposit() public {
        uint256 depositAmount = 100_000 ether;

        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(GRT), INDEXER_1)));

        mintGRT(address(this), depositAmount);
        GRT.approve(address(tenderizer), depositAmount);

        uint256 delTax = GRAPH_STAKING.delegationTaxPercentage();
        IGraphStaking.DelegationPool memory delPool = GRAPH_STAKING.delegationPools(INDEXER_1);
        IGraphStaking.Delegation memory delegation = GRAPH_STAKING.getDelegation(INDEXER_1, address(tenderizer));

        uint256 actualDeposit = depositAmount - (depositAmount * delTax / MAX_PPM);
        uint256 sharesOut = delPool.tokens != 0 ? actualDeposit * delPool.shares / delPool.tokens : actualDeposit;
        uint256 expected = sharesOut * (delPool.tokens + actualDeposit) / (delPool.shares + sharesOut);
        uint256 preview = tenderizer.previewDeposit(depositAmount);

        // TODO: this assertion might not hold with multiple deposits
        // and rounding error upon share calculation
        assertEq(preview, expected, "previewDeposit incorrect");
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: false, checkData: true });
        emit Deposit(address(this), address(this), depositAmount, expected);
        tenderizer.deposit(address(this), depositAmount);

        assertEq(tenderizer.totalSupply(), expected, "total supply incorrect");
        assertEq(tenderizer.balanceOf(address(this)), expected, "balance incorrect");

        delPool = GRAPH_STAKING.delegationPools(INDEXER_1);
        delegation = GRAPH_STAKING.getDelegation(INDEXER_1, address(tenderizer));
        uint256 staked = delegation.shares * delPool.tokens / delPool.shares;
        assertEq(tenderizer.totalSupply(), staked, "total staked incorrect");
    }

    function test_unlock_withdraw_simple() public {
        uint256 depositAmount = 100_000 ether;
        uint256 unstakeAmount = 50_000 ether;
        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(GRT), INDEXER_1)));
        mintGRT(address(this), depositAmount);
        GRT.approve(address(tenderizer), depositAmount);
        uint256 tTokenOut = tenderizer.deposit(address(this), depositAmount);

        vm.expectEmit();
        emit Unlock(address(this), unstakeAmount, 1);
        IGraphStaking.DelegationPool memory delPool = GRAPH_STAKING.delegationPools(INDEXER_1);

        uint256 unlockID = tenderizer.unlock(unstakeAmount);
        assertEq(unlockID, 1, "unlockID incorrect");
        assertEq(tenderizer.totalSupply(), tTokenOut - unstakeAmount, "total supply incorrect");
        assertEq(tenderizer.balanceOf(address(this)), tTokenOut - unstakeAmount, "balance incorrect");
        IGraphStaking.Delegation memory delegation = GRAPH_STAKING.getDelegation(INDEXER_1, address(tenderizer));
        uint256 actualUnstakedAmount = unstakeAmount * delPool.shares / delPool.tokens * delPool.tokens / delPool.shares;
        assertEq(delegation.tokensLocked, actualUnstakedAmount, "tokens locked incorrect");

        assertEq(tenderizer.unlockMaturity(unlockID), block.number + adapter.unlockTime(), "maturity incorrect");

        uint256 tokenId = uint256(bytes32(abi.encodePacked(tenderizer, uint96(unlockID))));

        Metadata memory metadata = fixture.unlocks.getMetadata(tokenId);
        assertEq(metadata.amount, unstakeAmount, "metadata amount incorrect");
        assertEq(metadata.maturity, block.number + adapter.unlockTime(), "metadata maturity incorrect");
        assertEq(metadata.progress, 0, "metadata progress incorrect");
        assertEq(metadata.unlockId, unlockID, "metadata unlockId incorrect");
        assertEq(metadata.validator, INDEXER_1, "metadata validator incorrect");

        // roll to 50% progress
        vm.roll(block.number + adapter.unlockTime() / 2);
        metadata = fixture.unlocks.getMetadata(tokenId);
        assertEq(metadata.progress, 50, "metadata progress incorrect");

        // roll to 100% progress and withdraw
        vm.roll(block.number + adapter.unlockTime() / 2 + 1);

        uint256 grtBalBeforeWithdraw = GRT.balanceOf(address(this));
        vm.expectEmit();
        emit Withdraw(address(this), actualUnstakedAmount, unlockID);
        uint256 withdrawn = Tenderizer(tenderizer).withdraw(address(this), unlockID);
        assertEq(withdrawn, actualUnstakedAmount, "withdrawn amount incorrect");
        delegation = GRAPH_STAKING.getDelegation(INDEXER_1, address(tenderizer));
        assertEq(delegation.tokensLocked, 0, "tokens locked not 0");
        vm.expectRevert("NOT_MINTED");
        fixture.unlocks.ownerOf(tokenId);
        assertEq(GRT.balanceOf(address(this)), grtBalBeforeWithdraw + actualUnstakedAmount, "GRT balance incorrect");
    }

    function test_rebase() public {
        Tenderizer tenderizer = Tenderizer(payable(fixture.factory.newTenderizer(address(GRT), INDEXER_1)));

        uint256 epochLength = IGraphEpochsTest(address(GRAPH_EPOCHS)).epochLength();
        // ======================================
        // Deposit & Process epoch
        uint256 depositAmount = 100_000 ether;

        mintGRT(address(this), depositAmount);
        GRT.approve(address(tenderizer), depositAmount);
        uint256 tTokenOut = tenderizer.deposit(address(this), depositAmount);
        vm.roll(block.number + epochLength);
        // ======================================

        // Allocate Rewards
        VmSafe.Wallet memory wallet = vm.createWallet("ALLOCATION_SIGNER");

        {
            bytes32 subgraphID = bytes32("SUBGRAPH");
            bytes32 metadata = bytes32("METADATA");

            // Curate subgraph
            mintGRT(address(this), 100_000 ether);
            GRT.approve(CURATION, 100_000 ether);
            IGraphCurationTest(CURATION).mint(subgraphID, 100_000 ether, 0);

            uint256 allocationAmount = 10_000 ether;
            mintGRT(INDEXER_1, 100_000 ether);
            vm.startPrank(INDEXER_1);
            GRT.approve(address(GRAPH_STAKING), 50_000 ether);
            IGraphStakingTest(address(GRAPH_STAKING)).stake(50_000 ether);
            bytes32 msgHash = keccak256(abi.encodePacked(INDEXER_1, wallet.addr));
            bytes32 digest = keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", msgHash));
            (uint8 v, bytes32 r, bytes32 s) = vm.sign(wallet, digest);
            IGraphStakingTest(address(GRAPH_STAKING)).allocate(
                subgraphID, allocationAmount, wallet.addr, metadata, abi.encodePacked(r, s, v)
            );
            vm.roll(block.number + epochLength);
        }

        // Close Allocation
        {
            bytes32 poi = bytes32("foo");

            IGraphStakingTest(address(GRAPH_STAKING)).closeAllocation(wallet.addr, poi);
        }
        vm.stopPrank();
        // ======================================
        {
            IGraphStaking.DelegationPool memory delPool = GRAPH_STAKING.delegationPools(INDEXER_1);

            tenderizer.rebase();
            uint256 delShares = GRAPH_STAKING.getDelegation(INDEXER_1, address(tenderizer)).shares;
            uint256 totalStaked = delShares * delPool.tokens / delPool.shares;
            assertEq(tenderizer.totalSupply(), totalStaked, "total supply incorrect");
            assertEq(tenderizer.balanceOf(address(this)), totalStaked, "balance incorrect");
            assertTrue(tenderizer.balanceOf(address(this)) > tTokenOut, "balance not greater than before");
        }
    }

    // TODO Rebase when there are pending unstakes in the current epoch
}
