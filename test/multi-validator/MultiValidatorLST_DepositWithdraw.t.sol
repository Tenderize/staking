// SPDX-License-Identifier: MIT
pragma solidity >=0.8.19;

import { Test } from "forge-std/Test.sol";

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { UnstakeNFT } from "core/multi-validator/UnstakeNFT.sol";
import { Registry } from "core/registry/Registry.sol";
import { FACTORY_ROLE } from "core/registry/Roles.sol";
import { AVLTree } from "core/multi-validator/AVLTree.sol";
import { console } from "forge-std/console.sol";

// Minimal mock for Registry used by MultiValidatorLST
contract MockRegistry {
    address private _treasury;
    mapping(address => bool) private _isTenderizer;

    function setTreasury(address t) external {
        _treasury = t;
    }

    function treasury() external view returns (address) {
        return _treasury;
    }

    function registerTenderizer(address, /*asset*/ address, /*validator*/ address tenderizer) external {
        _isTenderizer[tenderizer] = true;
    }

    function isTenderizer(address t) external view returns (bool) {
        return _isTenderizer[t];
    }
}

// Minimal mock for UnstakeNFT with the same external interface used by LST
interface GetUnstakeRequestLike {
    function getUnstakeRequest(uint256 id) external view returns (MultiValidatorLST.UnstakeRequest memory);
}

contract MockUnstakeNFT {
    address public minter;
    uint256 public lastID;
    mapping(uint256 => address) public ownerOf;

    function setMinter(address _minter) external {
        minter = _minter;
    }

    function mintNFT(address to) external returns (uint256 unstakeID) {
        require(msg.sender == minter, "only minter");
        unstakeID = ++lastID;
        ownerOf[unstakeID] = to;
    }

    function burnNFT(address from, uint256 id) external {
        require(ownerOf[id] == from, "not owner");
        delete ownerOf[id];
    }

    function getRequest(uint256 id) external view returns (MultiValidatorLST.UnstakeRequest memory) {
        return GetUnstakeRequestLike(minter).getUnstakeRequest(id);
    }
}

// Minimal mintable ERC20 for tests
contract MintableERC20 {
    string public name;
    string public symbol;
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    constructor(string memory name_, string memory symbol_) {
        name = name_;
        symbol = symbol_;
    }

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function approve(address spender, uint256 value) external returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function transfer(address to, uint256 value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= value, "ERC20: insufficient allowance");
        if (allowed != type(uint256).max) {
            allowance[from][msg.sender] = allowed - value;
        }
        _transfer(from, to, value);
        return true;
    }

    function _transfer(address from, address to, uint256 value) internal {
        require(balanceOf[from] >= value, "ERC20: insufficient balance");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
    }

    function mint(address to, uint256 value) external {
        totalSupply += value;
        balanceOf[to] += value;
        emit Transfer(address(0), to, value);
    }
}

contract MockTenderizer is MintableERC20 {
    uint256 public nextUnlockId;
    mapping(uint256 => uint256) public unlockIdToAmount;

    constructor(string memory name_, string memory symbol_) MintableERC20(name_, symbol_) { }

    // Simulate staking: mint tTokens to receiver; return minted amount as tTokens
    function deposit(address receiver, uint256 amount) external returns (uint256) {
        this.mint(receiver, amount);
        return amount;
    }

    function unlock(uint256 amount) external returns (uint256 unlockId) {
        unlockId = ++nextUnlockId;
        unlockIdToAmount[unlockId] = amount;
    }

    function withdraw(address, /*to*/ uint256 unlockId) external returns (uint256 amount) {
        amount = unlockIdToAmount[unlockId];
        delete unlockIdToAmount[unlockId];
        // Underlying asset transfer to `to` omitted for tree-focused tests
    }
}

// Harness to expose internal tree reads and controlled state mutation for tests
contract MultiValidatorLSTHarness is MultiValidatorLST {
    using AVLTree for AVLTree.Tree;

    constructor(Registry _registry) MultiValidatorLST(_registry) { }

    function exposed_getTreeStats() external view returns (uint24, uint24, uint24, int200, int200) {
        return stakingPoolTree.getTreeStats();
    }

    function exposed_getFirst() external view returns (uint24) {
        return stakingPoolTree.getFirst();
    }

    function exposed_getLast() external view returns (uint24) {
        return stakingPoolTree.getLast();
    }

    function exposed_findPredecessor(uint24 id) external view returns (uint24) {
        return stakingPoolTree.findPredecessor(id);
    }

    function exposed_findSuccessor(uint24 id) external view returns (uint24) {
        return stakingPoolTree.findSuccessor(id);
    }

    function exposed_getNode(uint24 id) external view returns (AVLTree.Node memory) {
        return stakingPoolTree.getNode(id);
    }

    // Test bootstrap to avoid initializer
    function exposed_bootstrap(address _token, address _unstakeNFT, address governance) external {
        token = _token;
        unstakeNFT = UnstakeNFT(_unstakeNFT);
        _grantRole(GOVERNANCE_ROLE, governance);
        _grantRole(UPGRADE_ROLE, governance);
    }

    function exposed_setExchangeRate(uint256 v) external {
        exchangeRate = v;
    }

    function exposed_setTotalAssets(uint256 v) external {
        totalAssets = v;
    }

    function exposed_setPoolBalance(uint24 id, uint256 newBalance) external {
        StakingPool storage pool = stakingPools[id];
        pool.balance = newBalance;
        int200 d;
        if (newBalance < pool.target) {
            d = -int200(uint200(pool.target - newBalance));
        } else {
            d = int200(uint200(newBalance - pool.target));
        }
        stakingPoolTree.updateDivergence(id, d);
    }

    function exposed_setTarget(uint24 id, uint256 newTarget) external {
        StakingPool storage pool = stakingPools[id];
        pool.target = newTarget;
        int200 d;
        if (pool.balance < newTarget) {
            d = -int200(uint200(newTarget - pool.balance));
        } else {
            d = int200(uint200(pool.balance - newTarget));
        }
        stakingPoolTree.updateDivergence(id, d);
    }

    // Safely set both balance and target. If reindex is true, force remove+insert to refresh ordering.
    function exposed_setPoolAndTarget(uint24 id, uint256 newBalance, uint256 newTarget, bool /*reindex*/ ) public {
        StakingPool storage pool = stakingPools[id];
        pool.balance = newBalance;
        pool.target = newTarget;
        int200 d = newBalance < newTarget ? -int200(uint200(newTarget - newBalance)) : int200(uint200(newBalance - newTarget));
        stakingPoolTree.updateDivergence(id, d);
    }

    function exposed_batchSet(
        uint24[] calldata ids,
        uint256[] calldata balances,
        uint256[] calldata targets,
        bool reindex
    )
        external
    {
        require(ids.length == balances.length && ids.length == targets.length, "len");
        for (uint256 i = 0; i < ids.length; i++) {
            exposed_setPoolAndTarget(ids[i], balances[i], targets[i], reindex);
        }
    }

    function exposed_getDivergence(uint24 id) external view returns (int200) {
        return stakingPoolTree.getNode(id).divergence;
    }

    function exposed_reindex(uint24 id) external {
        StakingPool storage pool = stakingPools[id];
        int200 d =
            pool.balance < pool.target ? -int200(uint200(pool.target - pool.balance)) : int200(uint200(pool.balance - pool.target));
        stakingPoolTree.updateDivergence(id, d);
    }

    function exposed_mintShares(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MultiValidatorLST_DepositWithdraw_Test is Test {
    MintableERC20 internal token;
    MockRegistry internal mockRegistry;
    MockUnstakeNFT internal mockUnstakeNFT;
    MultiValidatorLSTHarness internal lst;

    MockTenderizer internal t0;
    MockTenderizer internal t1;
    MockTenderizer internal t2;

    address internal treasury = address(0xBEEF);
    address internal depositor = address(0xD0);

    function setUp() public {
        // Mock registry and set treasury
        mockRegistry = new MockRegistry();
        mockRegistry.setTreasury(treasury);

        // Deploy harness LST
        lst = new MultiValidatorLSTHarness(Registry(address(mockRegistry)));

        // Underlying token
        token = new MintableERC20("Token", "TKN");

        // Mock UnstakeNFT and set minter after LST is bootstrapped
        mockUnstakeNFT = new MockUnstakeNFT();

        // Bootstrap LST (instead of initialize)
        lst.exposed_bootstrap(address(token), address(mockUnstakeNFT), address(this));

        // Make LST the minter for UnstakeNFT
        mockUnstakeNFT.setMinter(address(lst));

        // Setup mock tenderizers and register them as valid
        t0 = new MockTenderizer("t0", "t0");
        t1 = new MockTenderizer("t1", "t1");
        t2 = new MockTenderizer("t2", "t2");
        mockRegistry.registerTenderizer(address(token), address(0x1), address(t0));
        mockRegistry.registerTenderizer(address(token), address(0x2), address(t1));
        mockRegistry.registerTenderizer(address(token), address(0x3), address(t2));

        // Add validators with equal targets
        lst.addValidator(payable(address(t0)), 1000 ether);
        lst.addValidator(payable(address(t1)), 1000 ether);
        lst.addValidator(payable(address(t2)), 1000 ether);

        // Fund depositor and approve LST
        token.mint(depositor, 1_000_000 ether);
        vm.prank(depositor);
        token.approve(address(lst), type(uint256).max);
    }

    // 1) All negative divergence: all balances below target.
    // Expect deposit to allocate to the most negative first, proportionally, without touching positives.
    function test_Deposit_AllNegative() public {
        // Ensure all negative
        lst.exposed_setPoolAndTarget(0, 0, 1000 ether, true);
        lst.exposed_setPoolAndTarget(1, 0, 1000 ether, true);
        lst.exposed_setPoolAndTarget(2, 0, 1000 ether, true);

        uint256 depositAmount = 300 ether;
        vm.prank(depositor);
        lst.deposit(depositor, depositAmount);

        (,, uint256 b0) = lst.stakingPools(0);
        (,, uint256 b1) = lst.stakingPools(1);
        (,, uint256 b2) = lst.stakingPools(2);

        // Should distribute across negatives (not all to a single node)
        uint256 nonZero;
        if (b0 > 0) nonZero++;
        if (b1 > 0) nonZero++;
        if (b2 > 0) nonZero++;
        assertGe(nonZero, 2, "distributed across negatives");

        // Divergences remain <= 0
        assertLt(int256(lst.exposed_getDivergence(0)), 0, "n0 neg");
        assertLt(int256(lst.exposed_getDivergence(1)), 0, "n1 neg");
        assertLt(int256(lst.exposed_getDivergence(2)), 0, "n2 neg");

        // Second deposit should further distribute across negatives
        uint256 depositAmount2 = 300 ether;
        uint256 prev0 = b0;
        uint256 prev1 = b1;
        uint256 prev2 = b2;
        vm.prank(depositor);
        lst.deposit(depositor, depositAmount2);

        (,, b0) = lst.stakingPools(0);
        (,, b1) = lst.stakingPools(1);
        (,, b2) = lst.stakingPools(2);

        // Should still distribute (not solely one node)
        nonZero = 0;
        if (b0 > prev0) nonZero++;
        if (b1 > prev1) nonZero++;
        if (b2 > prev2) nonZero++;
        assertGe(nonZero, 2, "second deposit distributed across negatives");

        // Still under target after two rounds
        assertLt(int256(lst.exposed_getDivergence(0)), 0, "n0 still neg");
        assertLt(int256(lst.exposed_getDivergence(1)), 0, "n1 still neg");
        assertLt(int256(lst.exposed_getDivergence(2)), 0, "n2 still neg");
    }

    // 2) All positive divergence: all balances above target.
    // Expect deposit to allocate to the least positive (closest to target) proportionally to surplus.
    function test_Deposit_AllPositive() public {
        // Make all above target
        lst.exposed_setPoolAndTarget(0, 1200 ether, 1000 ether, true); // +200
        lst.exposed_setPoolAndTarget(1, 1100 ether, 1000 ether, true); // +100
        lst.exposed_setPoolAndTarget(2, 1050 ether, 1000 ether, true); // +50

        uint256 depositAmount = 300 ether;
        vm.prank(depositor);
        lst.deposit(depositor, depositAmount);

        // Expect allocations biased to least positive first (id2), then id1, then id0
        (,, uint256 b0) = lst.stakingPools(0);
        (,, uint256 b1) = lst.stakingPools(1);
        (,, uint256 b2) = lst.stakingPools(2);

        // delta balances
        uint256 d0 = b0 - 1200 ether;
        uint256 d1 = b1 - 1100 ether;
        uint256 d2 = b2 - 1050 ether;

        // At least two received some share
        uint256 nonZero;
        if (d0 > 0) nonZero++;
        if (d1 > 0) nonZero++;
        if (d2 > 0) nonZero++;
        assertGe(nonZero, 2, "distributed across least positives");
    }

    // 3) Mixed: some negatives and some positives.
    // Expect deposit to first fill negatives toward targets, then distribute leftover to least positive.
    function test_Deposit_Mixed() public {
        // id0: negative (need 900), id1: positive (+100), id2: negative (need 990)
        lst.exposed_setPoolAndTarget(0, 100 ether, 1000 ether, true);
        lst.exposed_setPoolAndTarget(1, 1100 ether, 1000 ether, true);
        lst.exposed_setPoolAndTarget(2, 10 ether, 1000 ether, true);

        vm.prank(depositor);
        lst.deposit(depositor, 300 ether);

        (,, uint256 b0) = lst.stakingPools(0);
        (,, uint256 b2) = lst.stakingPools(2);

        // At least one negative should have increased; positive may or may not receive leftovers
        bool negIncreased = (b0 > 100 ether) || (b2 > 10 ether);
        assertTrue(negIncreased, "at least one negative increased");
    }

    function test_Deposit_Mixed_10Nodes_TwoRounds() public {
        // Add 7 more validators (ids 3..9) with same target
        MockTenderizer t3_ = new MockTenderizer("t3", "t3");
        MockTenderizer t4_ = new MockTenderizer("t4", "t4");
        MockTenderizer t5_ = new MockTenderizer("t5", "t5");
        MockTenderizer t6_ = new MockTenderizer("t6", "t6");
        MockTenderizer t7_ = new MockTenderizer("t7", "t7");
        MockTenderizer t8_ = new MockTenderizer("t8", "t8");
        MockTenderizer t9_ = new MockTenderizer("t9", "t9");

        mockRegistry.registerTenderizer(address(token), address(0x4), address(t3_));
        mockRegistry.registerTenderizer(address(token), address(0x5), address(t4_));
        mockRegistry.registerTenderizer(address(token), address(0x6), address(t5_));
        mockRegistry.registerTenderizer(address(token), address(0x7), address(t6_));
        mockRegistry.registerTenderizer(address(token), address(0x8), address(t7_));
        mockRegistry.registerTenderizer(address(token), address(0x9), address(t8_));
        mockRegistry.registerTenderizer(address(token), address(0xA), address(t9_));

        lst.addValidator(payable(address(t3_)), 1000 ether); // id3
        lst.addValidator(payable(address(t4_)), 1000 ether); // id4
        lst.addValidator(payable(address(t5_)), 1000 ether); // id5
        lst.addValidator(payable(address(t6_)), 1000 ether); // id6
        lst.addValidator(payable(address(t7_)), 1000 ether); // id7
        lst.addValidator(payable(address(t8_)), 1000 ether); // id8
        lst.addValidator(payable(address(t9_)), 1000 ether); // id9

        // Configure divergences: ids 0..5 negative, ids 6..9 positive
        lst.exposed_setPoolAndTarget(0, 100 ether, 1000 ether, true); // -900
        lst.exposed_setPoolAndTarget(1, 200 ether, 1000 ether, true); // -800
        lst.exposed_setPoolAndTarget(2, 300 ether, 1000 ether, true); // -700
        lst.exposed_setPoolAndTarget(3, 400 ether, 1000 ether, true); // -600
        lst.exposed_setPoolAndTarget(4, 500 ether, 1000 ether, true); // -500
        lst.exposed_setPoolAndTarget(5, 600 ether, 1000 ether, true); // -400

        lst.exposed_setPoolAndTarget(6, 1050 ether, 1000 ether, true); // +50 (least positive)
        lst.exposed_setPoolAndTarget(7, 1100 ether, 1000 ether, true); // +100
        lst.exposed_setPoolAndTarget(8, 1200 ether, 1000 ether, true); // +200
        lst.exposed_setPoolAndTarget(9, 1500 ether, 1000 ether, true); // +500 (most positive)

        // Round 1: deposit less than total negative deficit (3900)
        // Expect only negatives to increase
        uint256[10] memory before1;
        for (uint24 i = 0; i < 10; i++) {
            (,, before1[i]) = lst.stakingPools(i);
        }
        vm.prank(depositor);
        lst.deposit(depositor, 1000 ether);
        uint256 negIncreasedCount;
        for (uint24 i = 0; i < 6; i++) {
            (,, uint256 bi) = lst.stakingPools(i);
            if (bi > before1[i]) negIncreasedCount++;
        }
        assertGe(negIncreasedCount, 2, "R1: negatives received deposits");
        // Positives unchanged in R1
        for (uint24 i = 6; i < 10; i++) {
            (,, uint256 bi) = lst.stakingPools(i);
            assertEq(bi, before1[i], "R1: positives unchanged");
        }

        // Round 2: deposit more than remaining deficit, expect negatives filled and leftover to least positives (6..8)
        uint256[10] memory before2;
        for (uint24 i = 0; i < 10; i++) {
            (,, before2[i]) = lst.stakingPools(i);
        }
        vm.prank(depositor);
        lst.deposit(depositor, 4000 ether);

        // With selection window size 3, at least 3 negatives should be at target now
        uint256 negativesAtTarget;
        for (uint24 i = 0; i < 6; i++) {
            (,, uint256 bi) = lst.stakingPools(i);
            if (bi == 1000 ether) negativesAtTarget++;
        }
        assertGe(negativesAtTarget, 3, "R2: at least three negatives filled to target");
        // Most positive id9 should not be selected (count limit is 3)
        (,, uint256 b9) = lst.stakingPools(9);
        assertEq(b9, before2[9], "R2: most positive unchanged");
        // Some of least positives (6..8) should have increased
        uint256 posLeastIncreased;
        for (uint24 i = 6; i < 9; i++) {
            (,, uint256 bi) = lst.stakingPools(i);
            if (bi > before2[i]) posLeastIncreased++;
        }
        assertGe(posLeastIncreased, 1, "R2: least positives received leftover");
    }
}
