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

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { Multicallable } from "solady/utils/Multicallable.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SelfPermit } from "core/utils/SelfPermit.sol";
import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";

import { ERC20 } from "solady/tokens/ERC20.sol";

import { Tenderizer } from "core/tenderizer/Tenderizer.sol";

import { AVLTree } from "core/multi-validator/AVLTree.sol";

import { UnstakeNFT } from "core/multi-validator/UnstakeNFT.sol";
import { Registry } from "core/registry/Registry.sol";

import { console2 } from "forge-std/console2.sol";

contract MultiValidatorLST is
    ERC20,
    ERC721Receiver,
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    Multicallable,
    SelfPermit
{
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;
    using AVLTree for AVLTree.Tree;

    bytes32 constant MINTER_ROLE = keccak256("MINTER");
    bytes32 constant UPGRADE_ROLE = keccak256("UPGRADE");
    bytes32 constant GOVERNANCE_ROLE = keccak256("GOVERNANCE");

    uint256 constant MAX_FEE = 0.1e6; // 10%
    uint256 constant FEE_WAD = 1e6; // 100%

    struct UnstakeRequest {
        uint256 amount; // expected amount to receive
        uint64 createdAt; // block timestamp
        address[] tTokens; // addresses of the tTokens unstaked
        uint256[] unlockIDs; // IDs of the unlocks
    }

    // Temporary structure for reindexing operation
    struct ValidatorData {
        uint24 id;
        address payable tToken;
        uint256 target;
        uint256 balance;
        int200 divergence;
    }

    error DepositTooSmall();
    error BalanceNotZero();
    error UnstakeSlippage();
    error RebalanceFailed(address target, bytes data, uint256 value);
    error InvalidTenderizer(address tToken);

    // Events
    event Deposit(address indexed sender, uint256 amount, uint256 shares);
    event Unstake(address indexed sender, uint256 unstakeID, uint256 shares, uint256 amount);
    event Unwrap(address indexed sender, uint256 shares, uint256 amount);
    event Withdraw(address indexed sender, uint256 unstakeID, uint256 amount);
    event ValidatorAdded(uint256 indexed id, address tToken, uint256 target);
    event ValidatorRemoved(uint256 indexed id);
    event WeightsUpdated(uint256[] ids, uint256[] weights);
    event Rebalanced(uint256 indexed id, uint256 amount, bool isDeposit);

    // Struct to track validator share info
    struct StakingPool {
        address payable tToken; // Address of validator share token
        uint256 target; // Target weight (basis points)
        uint256 balance; // Current balance of tTokens
    }

    // === IMMUTABLES ===
    Registry immutable registry;

    // === GLOBAL STATE ===
    address public token; // Underlying asset (e.g. ETH)
    UnstakeNFT unstakeNFT;
    uint256 public fee; // Stored as fixed point (1e18)
    uint256 public totalAssets;
    uint256 private lastUnstakeID;
    uint256 public exchangeRate = FixedPointMathLib.WAD; // Stored as fixed point (1e18)

    mapping(uint24 id => StakingPool) public stakingPools;
    mapping(uint256 unstakeID => UnstakeRequest) private unstakeRequests;
    AVLTree.Tree public stakingPoolTree;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(Registry _registry) {
        _disableInitializers();
        // Set initial state
        registry = _registry;
    }

    function name() public view override returns (string memory) {
        return string.concat("Steaked ", ERC20(token).symbol());
    }

    function symbol() public view override returns (string memory) {
        return string.concat("st", ERC20(token).symbol());
    }

    function getUnstakeRequest(uint256 id) external view returns (UnstakeRequest memory) {
        return unstakeRequests[id];
    }

    function initialize(address _token, UnstakeNFT _unstakeNFT, address treasury) external initializer {
        __AccessControl_init();
        _grantRole(UPGRADE_ROLE, treasury);
        _grantRole(GOVERNANCE_ROLE, treasury);

        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(MINTER_ROLE, GOVERNANCE_ROLE);
        // Only allow UPGRADE_ROLE to add new UPGRADE_ROLE memebers
        // If all members of UPGRADE_ROLE are revoked, contract upgradability is revoked
        _setRoleAdmin(UPGRADE_ROLE, UPGRADE_ROLE);

        token = _token;
        unstakeNFT = _unstakeNFT;
        exchangeRate = FixedPointMathLib.WAD;
    }

    // Core functions for deposits
    function _depositToPool(uint24 id, uint256 amount) internal returns (uint256 tTokensReceived) {
        if (amount == 0) return 0;
        StakingPool storage pool = stakingPools[id];
        ERC20(token).approve(pool.tToken, amount);
        uint256 tTokens = Tenderizer(pool.tToken).deposit(address(this), amount);
        pool.balance += tTokens;
        int200 d =
            pool.balance < pool.target ? -int200(uint200(pool.target - pool.balance)) : int200(uint200(pool.balance - pool.target));
        stakingPoolTree.updateDivergence(id, d);
        return tTokens;
    }

    function _fillNegatives(uint24[] memory ids, uint256 assets) internal returns (uint256 received, uint256 consumed) {
        uint256 remaining = assets;
        uint256 len = ids.length;
        for (uint256 i = 0; i < len; i++) {
            uint24 id = ids[i];
            StakingPool storage p = stakingPools[id];
            uint256 need = p.target - p.balance;
            uint256 amt = need < remaining ? need : remaining;
            if (amt == 0) continue;
            uint256 tTokens = _depositToPool(id, amt);
            received += tTokens;
            remaining -= amt;
            if (remaining == 0) break;
        }
        consumed = assets - remaining;
    }

    function _distributeLeastPositives(uint24[] memory ids, uint256 leftover) internal returns (uint256 received) {
        if (leftover == 0 || ids.length == 0) return 0;
        // Sum surplus
        uint256 len = ids.length;
        uint256 posSum = 0;
        for (uint256 i = 0; i < len; i++) {
            StakingPool storage p = stakingPools[ids[i]];
            uint256 surplus = p.balance > p.target ? (p.balance - p.target) : 0;
            posSum += surplus;
        }
        if (posSum == 0) return 0;
        uint256 allocated = 0;
        for (uint256 i = 0; i < len; i++) {
            StakingPool storage p = stakingPools[ids[i]];
            uint256 surplus = p.balance > p.target ? (p.balance - p.target) : 0;
            uint256 amt = leftover * surplus / posSum;
            if (i == 0 && amt < leftover) {
                // allocate any dust to first bucket later
            }
            if (amt > 0) {
                received += _depositToPool(ids[i], amt);
                allocated += amt;
            }
        }
        // Allocate any dust remainder to the first id to avoid keeping idle funds
        if (allocated < leftover) {
            uint256 dust = leftover - allocated;
            received += _depositToPool(ids[0], dust);
        }
    }

    function deposit(address receiver, uint256 assets) external returns (uint256 shares) {
        // Transfer assets from sender
        token.safeTransferFrom(msg.sender, address(this), assets);

        // Stake assets
        uint24 count = 3;

        (, uint24 positiveNodes, uint24 negativeNodes,, int200 negDivergence) = stakingPoolTree.getTreeStats();

        console2.log("negativeNodes", uint256(negativeNodes));
        console2.log("positiveNodes", uint256(positiveNodes));

        uint256 negDiv_ = uint256(int256(-(negDivergence)));

        uint256 received;
        int200 totalDivergence = 0;
        if (assets <= negDiv_) {
            uint24 maxCount = negativeNodes > count ? count : negativeNodes;
            StakingPool[] memory items = new StakingPool[](maxCount);

            (uint24[] memory validatorIDs,) = stakingPoolTree.findMostDivergent(false, maxCount);
            for (uint24 i = 0; i < maxCount; i++) {
                StakingPool storage pool = stakingPools[validatorIDs[i]];
                items[i] = StakingPool(pool.tToken, pool.target, pool.balance);
                totalDivergence += int200(int256((pool.target - pool.balance)));
            }

            for (uint24 i = 0; i < maxCount; i++) {
                uint256 amount = uint256(int256(assets) * int256(items[i].target - items[i].balance) / int256(totalDivergence));
                ERC20(token).approve(items[i].tToken, amount);
                uint256 tTokens = Tenderizer(items[i].tToken).deposit(address(this), amount);
                StakingPool storage pool = stakingPools[validatorIDs[i]];
                pool.balance += tTokens;
                received += tTokens;

                // Rebalance tree
                int200 d;
                if (pool.balance < pool.target) {
                    d = -int200(uint200(pool.target - pool.balance));
                } else {
                    d = int200(uint200(pool.balance - pool.target));
                }
                stakingPoolTree.updateDivergence(validatorIDs[i], d);
            }
        } else {
            // Phase 1: fully fill the most negative nodes up to their targets
            uint24 negCount = negativeNodes > count ? count : negativeNodes;
            (uint24[] memory negIDs,) = stakingPoolTree.findMostDivergent(false, negCount);
            uint256 consumed_;
            {
                (uint256 rcv, uint256 con) = _fillNegatives(negIDs, assets);
                received += rcv;
                consumed_ = con;
            }

            // Phase 2: distribute leftover across least-positive nodes proportionally to their surplus
            uint256 leftover = assets - consumed_;
            if (leftover > 0 && positiveNodes > 0) {
                uint24 posCount = positiveNodes > count ? count : positiveNodes;
                // Collect least-positive nodes by walking ascending order from first until divergence > 0
                uint24[] memory posIDs2 = new uint24[](posCount);
                uint24 found = 0;
                uint24 cur = stakingPoolTree.getFirst();
                while (cur != 0 && found < posCount) {
                    int200 div = stakingPoolTree.getNode(cur).divergence;
                    if (div > 0) {
                        posIDs2[found] = cur;
                        found++;
                    }
                    uint24 next_ = stakingPoolTree.findSuccessor(cur);
                    if (next_ == 0 || next_ == cur) break;
                    cur = next_;
                }
                // Trim to actual found length
                if (found < posCount) {
                    assembly {
                        mstore(posIDs2, found)
                    }
                }
                if (posIDs2.length > 0) {
                    received += _distributeLeastPositives(posIDs2, leftover);
                }
            }
        }

        totalAssets += received;
        // Calculate shares based on current exchange rate
        shares = received.divWad(exchangeRate);
        if (shares == 0) revert DepositTooSmall();
        // Mint shares to receiver
        _mint(receiver, shares);

        emit Deposit(msg.sender, assets, shares);
    }

    // TODO: Improve strategy of how much to draw from each validator with divergence ratio
    function unstake(uint256 shares, uint256 minAmount) external returns (uint256 unstakeID) {
        // Get unstakeID
        unstakeID = ++lastUnstakeID;

        // Calculate amount of tokens that need to be unstaked
        uint256 amount = shares.mulWad(exchangeRate);
        if (amount < minAmount) revert UnstakeSlippage();

        // Burn shares to prevent re-entrancy (after calculating amount !!)
        _burn(msg.sender, shares);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        address[] memory tTokens = new address[](k);
        uint256[] memory unlockIDs = new uint256[](k);
        // Start looping the tree from top to bottom
        uint256 remaining = amount;
        uint24 id = stakingPoolTree.getLast();

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                continue;
            }
            uint256 max = pool.balance - maxDrawdown; // Edge case with rounding
            uint256 draw = max < remaining ? max : remaining;
            tTokens[i] = pool.tToken;
            pool.balance -= draw;
            unlockIDs[i] = Tenderizer(pool.tToken).unlock(draw);

            // Get next id before updating
            uint24 nextId = stakingPoolTree.findPredecessor(id);

            int200 d;
            if (pool.balance < pool.target) {
                d = -int200(uint200(pool.target - pool.balance));
            } else {
                d = int200(uint200(pool.balance - pool.target));
            }
            stakingPoolTree.updateDivergence(id, d);
            if (draw == remaining) {
                break;
            }
            remaining -= draw;
            id = nextId;
        }

        // Create unstake NFT (needed to claim withdrawal)
        unstakeID = unstakeNFT.mintNFT(msg.sender);
        unstakeRequests[unstakeID] =
            UnstakeRequest({ amount: amount, createdAt: uint64(block.timestamp), tTokens: tTokens, unlockIDs: unlockIDs });

        // Update state
        totalAssets -= amount;

        emit Unstake(msg.sender, unstakeID, shares, amount);
    }

    // TODO: make non-reentrant
    function withdraw(uint256 unstakeID) external returns (uint256 amountReceived) {
        UnstakeRequest storage request = unstakeRequests[unstakeID];

        unstakeNFT.burnNFT(msg.sender, unstakeID);

        uint256 l = request.tTokens.length;
        // TODO: should we send withdrawals to our contract as an intermediate step ?
        for (uint256 i = 0; i < l; i++) {
            if (request.tTokens[i] == address(0)) continue;
            amountReceived += Tenderizer(payable(request.tTokens[i])).withdraw(msg.sender, request.unlockIDs[i]);
        }
        delete unstakeRequests[unstakeID];

        emit Withdraw(msg.sender, unstakeID, amountReceived);
    }

    // Can be used to flash unstake and sell the resulting assets in TenderSwap
    function unwrap(uint256 shares, uint256 minAmount) external returns (address[] memory tTokens, uint256[] memory amounts) {
        // Calculate amount of tokens that need to be unstaked
        uint256 amount = shares.mulWad(exchangeRate);
        if (amount < minAmount) revert UnstakeSlippage();

        // Burn shares to prevent re-entrancy (after calculating amount !!)
        _burn(msg.sender, shares);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        tTokens = new address[](k);
        amounts = new uint256[](k);
        // Start looping the tree from top to bottom
        uint256 remaining = amount;
        uint24 id = stakingPoolTree.getLast();
        uint256 index = 0;

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                // Didn't use this element so reduce the resulting array
                // sizes by 1
                if (tTokens.length > 0) {
                    assembly {
                        mstore(tTokens, sub(mload(tTokens), 1))
                        mstore(amounts, sub(mload(amounts), 1))
                    }
                }
                continue;
            }
            uint256 max = pool.balance - maxDrawdown; // Edge case with rounding
            uint256 draw = max < remaining ? max : remaining;
            tTokens[index] = pool.tToken;
            amounts[index] = draw;
            index++;
            pool.balance -= draw;

            // Get next id before updating
            uint24 nextId = stakingPoolTree.findPredecessor(id);

            int200 d;
            if (pool.balance < pool.target) {
                d = -int200(uint200(pool.target - pool.balance));
            } else {
                d = int200(uint200(pool.balance - pool.target));
            }
            stakingPoolTree.updateDivergence(id, d);
            SafeTransferLib.safeTransfer(pool.tToken, msg.sender, draw);
            if (draw == remaining) {
                break;
            }
            remaining -= draw;
            if (remaining == 0) {
                break;
            }
            id = nextId;
        }

        // End truncate unused elements
        if (tTokens.length > 0) {
            assembly {
                mstore(tTokens, index)
                mstore(amounts, index)
            }
        }

        // Update state
        totalAssets -= amount;

        emit Unwrap(msg.sender, shares, amount);
    }

    function previewUnwrap(uint256 shares) external view returns (address[] memory tTokens, uint256[] memory amounts) {
        if (shares > totalSupply()) revert InsufficientBalance();
        uint256 amount = shares.mulWad(exchangeRate);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        tTokens = new address[](k);
        amounts = new uint256[](k);
        uint24 id = stakingPoolTree.getLast();
        uint256 remaining = amount;
        uint256 index = 0;

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                // Didn't use this element so reduce the resulting array
                // sizes by 1
                if (tTokens.length > 0) {
                    assembly {
                        mstore(tTokens, sub(mload(tTokens), 1))
                        mstore(amounts, sub(mload(amounts), 1))
                    }
                }
                continue;
            }
            uint256 max = pool.balance - maxDrawdown; // Edge case with rounding
            uint256 draw = max < remaining ? max : remaining;
            tTokens[index] = pool.tToken;
            amounts[index] = draw;
            index++;
            remaining -= draw;
            if (remaining == 0) {
                break;
            }
            id = stakingPoolTree.findPredecessor(id);
        }

        // End truncate unused elements
        if (tTokens.length > 0) {
            assembly {
                mstore(tTokens, index)
                mstore(amounts, index)
            }
        }
    }

    function claimValidatorRewards(uint24 id) external {
        // Update the balance of the validator
        StakingPool storage pool = stakingPools[id];
        Tenderizer tenderizer = Tenderizer(pool.tToken);
        uint256 newBalance = tenderizer.balanceOf(address(this));
        uint256 currentBalance = pool.balance;
        if (newBalance > currentBalance) {
            uint256 fees = (newBalance - currentBalance) * fee / FEE_WAD;
            totalAssets += newBalance - currentBalance - fees;
            if (fees > 0) _mint(registry.treasury(), fees);
        } else {
            totalAssets -= currentBalance - newBalance;
        }

        int200 d;
        if (newBalance < pool.target) {
            d = -int200(uint200(pool.target - newBalance));
        } else {
            d = int200(uint200(newBalance - pool.target));
        }

        pool.balance = newBalance;
        exchangeRate = totalAssets.divWad(totalSupply());

        // Will revert if node doesn't exist in the tree
        stakingPoolTree.updateDivergence(id, d);
    }

    // Governance functions
    function addValidator(address payable tToken, uint200 target) external onlyRole(GOVERNANCE_ROLE) {
        // TODO: Validate tToken
        if (!registry.isTenderizer(tToken)) revert InvalidTenderizer(tToken);
        // TODO: would this work for ID ?
        uint24 id = stakingPoolTree.getSize();
        stakingPools[id] = StakingPool(tToken, target, 0);
        // TODO: if we consider the target as the validators full stake (including its total delegation) we would
        // need to initialise that here
        stakingPoolTree.insert(id, -int200(target));

        emit ValidatorAdded(id, tToken, target);
    }

    function validatorCount() external view returns (uint256) {
        return stakingPoolTree.getSize();
    }

    // This only updates the divergence of the current validator. Depending on the weighting used the divergences
    // for other validators may also need to be updated. The contract currently uses lazy-updating of divergences
    // when validators are next accessed.
    function removeValidator(uint24 id) external onlyRole(GOVERNANCE_ROLE) {
        // TODO: move the stake from this validator or require that this validator has no balance left
        if (stakingPools[id].balance > 0) revert BalanceNotZero();
        stakingPoolTree.remove(id);
        delete stakingPools[id];

        emit ValidatorRemoved(id);
    }

    function updateTarget(uint24 id, uint200 target) external onlyRole(GOVERNANCE_ROLE) {
        StakingPool storage pool = stakingPools[id];
        // update divergence, will revert if node doesn't exist in the tree
        int200 d;
        if (pool.balance < target) {
            d = -int200(target - uint200(pool.balance));
        } else {
            d = int200(target - uint200(pool.balance));
        }
        stakingPoolTree.updateDivergence(id, d);
        pool.target = target;
    }

    function setFee(uint256 _fee) external onlyRole(GOVERNANCE_ROLE) {
        if (_fee > MAX_FEE) revert();
        fee = _fee;
    }

    // Override required by UUPSUpgradeable
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADE_ROLE) { }

    /**
     * @notice One-off function to reindex the entire AVL tree structure
     * @dev This function should only be called once to fix a broken tree
     *      It extracts all validator data, clears the tree, and rebuilds it properly
     *      Protected by GOVERNANCE_ROLE for security
     */
    function reindexTree() external onlyRole(GOVERNANCE_ROLE) {
        // Step 1: Count existing validators and prepare array
        uint256 validatorTotal = 0;
        for (uint24 i = 0; i <= 20; i++) {
            // Check up to 20 validators (safe upper bound)
            if (stakingPools[i].tToken != address(0)) {
                validatorTotal++;
            }
        }

        // Step 2: Extract all existing validator data
        ValidatorData[] memory validators = new ValidatorData[](validatorTotal);
        uint256 index = 0;

        for (uint24 i = 0; i <= 20 && index < validatorTotal; i++) {
            StakingPool memory pool = stakingPools[i];

            // Check if this pool exists (has a tToken address)
            if (pool.tToken != address(0)) {
                // Calculate divergence
                int200 divergence;
                if (pool.balance < pool.target) {
                    divergence = -int200(uint200(pool.target - pool.balance));
                } else {
                    divergence = int200(uint200(pool.balance - pool.target));
                }

                validators[index] = ValidatorData({
                    id: i,
                    tToken: pool.tToken,
                    target: pool.target,
                    balance: pool.balance,
                    divergence: divergence
                });

                index++;
            }
        }

        // Step 3: Clear the existing tree structure
        // Reset tree state variables
        stakingPoolTree.root = 0;
        stakingPoolTree.first = 0;
        stakingPoolTree.last = 0;
        stakingPoolTree.size = 0;
        stakingPoolTree.positiveNodes = 0;
        stakingPoolTree.negativeNodes = 0;
        stakingPoolTree.posDivergence = 0;
        stakingPoolTree.negDivergence = 0;

        // Clear all node data
        for (uint24 i = 0; i <= 20; i++) {
            delete stakingPoolTree.nodes[i];
        }

        // Step 4: Sort validators by divergence (bubble sort for simplicity with small dataset)
        for (uint256 i = 0; i < validatorTotal; i++) {
            for (uint256 j = i + 1; j < validatorTotal; j++) {
                if (
                    validators[i].divergence > validators[j].divergence
                        || (validators[i].divergence == validators[j].divergence && validators[i].id > validators[j].id)
                ) {
                    // Swap
                    ValidatorData memory temp = validators[i];
                    validators[i] = validators[j];
                    validators[j] = temp;
                }
            }
        }

        // Step 5: Reinsert all validators in sorted order
        for (uint256 i = 0; i < validatorTotal; i++) {
            ValidatorData memory v = validators[i];

            // Reinsert into tree
            stakingPoolTree.insert(v.id, v.divergence);
        }
    }
}
