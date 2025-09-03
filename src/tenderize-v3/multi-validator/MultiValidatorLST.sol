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

pragma solidity ^0.8.25;

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { AccessControlUpgradeable } from "openzeppelin-contracts-upgradeable/access/AccessControlUpgradeable.sol";

import { Multicallable } from "solady/utils/Multicallable.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";
import { SelfPermit } from "core/utils/SelfPermit.sol";
import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";

import { ERC20 } from "solady/tokens/ERC20.sol";

import { Tenderizer } from "core/tenderize-v3/Tenderizer.sol";
import { Registry } from "core/tenderize-v3/registry/Registry.sol";
import { AVLTree } from "core/multi-validator/AVLTree.sol";
import { UnstakeNFT } from "core/tenderize-v3/multi-validator/UnstakeNFT.sol";

contract MultiValidatorLSTNative is
    ERC20,
    ERC721Receiver,
    Initializable,
    AccessControlUpgradeable,
    UUPSUpgradeable,
    Multicallable,
    SelfPermit
{
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
        address payable[] tenderizers; // tenderizer addresses
        uint256[] unlockIDs; // IDs of the unlocks from tenderizers
    }

    error DepositTooSmall();
    error BalanceNotZero();
    error UnstakeSlippage();
    error RebalanceFailed(address target, bytes data, uint256 value);
    error InvalidTenderizer(address tToken);
    error TransferFailed();

    // Events
    event Deposit(address indexed sender, uint256 amount, uint256 shares);
    event Unstake(address indexed sender, uint256 unstakeID, uint256 shares, uint256 amount);
    event Unwrap(address indexed sender, uint256 shares, uint256 amount);
    event Withdraw(address indexed sender, uint256 unstakeID, uint256 amount);
    event ValidatorAdded(uint256 indexed id, address tenderizer, uint256 target);
    event ValidatorRemoved(uint256 indexed id);
    event WeightsUpdated(uint256[] ids, uint256[] weights);
    event Rebalanced(uint256 indexed id, uint256 amount, bool isDeposit);

    // Struct to track validator staking info
    struct StakingPool {
        address payable tToken; // Tenderizer contract for this validator
        uint256 target; // Target weight (in native token units)
        uint256 balance; // Current balance staked with this validator
    }

    // === IMMUTABLES ===
    Registry immutable registry;

    // === GLOBAL STATE ===
    string public tokenSymbol; // Symbol of the native token (e.g., "ETH", "SEI")
    UnstakeNFT public unstakeNFT;
    uint256 public fee; // Stored as fixed point (1e6)
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
        return string.concat("Steaked ", tokenSymbol);
    }

    function symbol() public view override returns (string memory) {
        return string.concat("st", tokenSymbol);
    }

    function getUnstakeRequest(uint256 id) external view returns (UnstakeRequest memory) {
        return unstakeRequests[id];
    }

    function initialize(string memory _tokenSymbol, UnstakeNFT _unstakeNFT, address treasury) external initializer {
        __AccessControl_init();

        _grantRole(UPGRADE_ROLE, treasury);
        _grantRole(GOVERNANCE_ROLE, treasury);

        _setRoleAdmin(GOVERNANCE_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(MINTER_ROLE, GOVERNANCE_ROLE);
        _setRoleAdmin(UPGRADE_ROLE, UPGRADE_ROLE);

        tokenSymbol = _tokenSymbol;
        unstakeNFT = _unstakeNFT;
        exchangeRate = FixedPointMathLib.WAD;
    }

    // Internal helpers for deposits
    function _depositToPool(uint24 id, uint256 amount) internal returns (uint256 staked) {
        if (amount == 0) return 0;
        StakingPool storage pool = stakingPools[id];
        staked = Tenderizer(payable(pool.tToken)).deposit{ value: amount }(address(this));
        pool.balance += staked;
        int200 d = _calculateDivergence(pool.balance, pool.target);
        stakingPoolTree.updateDivergence(id, d);
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
            uint256 staked = _depositToPool(id, amt);
            received += staked;
            remaining -= amt;
            if (remaining == 0) break;
        }
        consumed = assets - remaining;
    }

    function _distributeLeastPositives(uint24[] memory ids, uint256 leftover) internal returns (uint256 received) {
        if (leftover == 0 || ids.length == 0) return 0;
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
            if (amt > 0) {
                received += _depositToPool(ids[i], amt);
                allocated += amt;
            }
        }
        if (allocated < leftover) {
            uint256 dust = leftover - allocated;
            received += _depositToPool(ids[0], dust);
        }
    }

    // Core functions for deposits - now payable for native tokens
    function deposit(address receiver) external payable returns (uint256 shares) {
        uint256 assets = msg.value;

        // Stake assets across validators
        uint24 count = 3;
        (, uint24 positiveNodes, uint24 negativeNodes,, int200 negDivergence) = stakingPoolTree.getTreeStats();

        uint256 negDiv_ = uint256(int256(-negDivergence));
        uint256 received;
        int200 totalDivergence = 0;

        if (assets <= negDiv_) {
            // Fill negative divergence validators first
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

                // Stake through tenderizer (native token)
                uint256 staked = Tenderizer(payable(items[i].tToken)).deposit{ value: amount }(address(this));

                StakingPool storage pool = stakingPools[validatorIDs[i]];
                pool.balance += staked;
                received += staked;

                // Rebalance tree
                int200 d = _calculateDivergence(pool.balance, pool.target);
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

    function unstake(uint256 shares, uint256 minAmount) external returns (uint256 unstakeID) {
        if (shares > balanceOf(msg.sender)) revert InsufficientBalance();

        // Calculate amount of tokens that need to be unstaked
        uint256 amount = shares.mulWad(exchangeRate);
        if (amount < minAmount) revert UnstakeSlippage();

        // Burn shares to prevent re-entrancy
        _burn(msg.sender, shares);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        address payable[] memory tenderizers = new address payable[](k);
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

            uint256 max = pool.balance - maxDrawdown;
            uint256 draw = max < remaining ? max : remaining;

            tenderizers[i] = pool.tToken;
            pool.balance -= draw;

            // Unlock through tenderizer
            unlockIDs[i] = Tenderizer(payable(pool.tToken)).unlock(draw);

            // Get next id before updating
            uint24 nextId = stakingPoolTree.findPredecessor(id);

            // Update divergence
            int200 d = _calculateDivergence(pool.balance, pool.target);
            stakingPoolTree.updateDivergence(id, d);

            if (draw == remaining) {
                break;
            }
            remaining -= draw;
            id = nextId;
        }

        // Create unstake NFT
        unstakeID = unstakeNFT.mintNFT(msg.sender);
        unstakeRequests[unstakeID] =
            UnstakeRequest({ amount: amount, createdAt: uint64(block.timestamp), tenderizers: tenderizers, unlockIDs: unlockIDs });

        // Update state
        totalAssets -= amount;

        emit Unstake(msg.sender, unstakeID, shares, amount);
    }

    function withdraw(uint256 unstakeID) external returns (uint256 amountReceived) {
        UnstakeRequest storage request = unstakeRequests[unstakeID];

        // Burn NFT
        unstakeNFT.burnNFT(msg.sender, unstakeID);

        uint256 l = request.tenderizers.length;
        for (uint256 i = 0; i < l; i++) {
            if (request.tenderizers[i] == address(0)) continue;

            amountReceived += Tenderizer(request.tenderizers[i]).withdraw(payable(address(this)), request.unlockIDs[i]);
        }

        delete unstakeRequests[unstakeID];

        // Send native tokens to user
        if (amountReceived > 0) {
            (bool success,) = payable(msg.sender).call{ value: amountReceived }("");
            if (!success) revert TransferFailed();
        }

        emit Withdraw(msg.sender, unstakeID, amountReceived);
    }

    function unwrap(
        uint256 shares,
        uint256 minAmount
    )
        external
        returns (address payable[] memory tenderizers, uint256[] memory amounts)
    {
        if (shares > balanceOf(msg.sender)) revert InsufficientBalance();

        // Calculate amount
        uint256 amount = shares.mulWad(exchangeRate);
        if (amount < minAmount) revert UnstakeSlippage();

        // Burn shares
        _burn(msg.sender, shares);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        tenderizers = new address payable[](k);
        amounts = new uint256[](k);

        uint256 remaining = amount;
        uint24 id = stakingPoolTree.getLast();
        uint256 index = 0;

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                continue;
            }

            uint256 max = pool.balance - maxDrawdown;
            uint256 draw = max < remaining ? max : remaining;

            tenderizers[index] = pool.tToken;
            amounts[index] = draw;
            index++;
            pool.balance -= draw;

            // Get next id before updating
            uint24 nextId = stakingPoolTree.findPredecessor(id);

            // Update divergence
            int200 d = _calculateDivergence(pool.balance, pool.target);
            stakingPoolTree.updateDivergence(id, d);

            // Note: In unwrap, we return tenderizer addresses and amounts
            // The caller can handle the actual unstaking/withdrawal separately

            if (draw == remaining) {
                break;
            }
            remaining -= draw;
            if (remaining == 0) {
                break;
            }
            id = nextId;
        }

        // Resize arrays
        assembly {
            mstore(tenderizers, index)
            mstore(amounts, index)
        }

        totalAssets -= amount;

        emit Unwrap(msg.sender, shares, amount);
    }

    function claimValidatorRewards(uint24 id) external {
        // Update the balance of the validator
        StakingPool storage pool = stakingPools[id];
        Tenderizer tenderizer = Tenderizer(pool.tToken);
        uint256 newBalance = tenderizer.balanceOf(address(this));
        uint256 currentBalance = pool.balance;
        if (newBalance > currentBalance) {
            uint256 fees = newBalance - currentBalance * fee / FEE_WAD;
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

    function removeValidator(uint24 id) external onlyRole(GOVERNANCE_ROLE) {
        if (stakingPools[id].balance > 0) revert BalanceNotZero();

        stakingPoolTree.remove(id);
        delete stakingPools[id];

        emit ValidatorRemoved(id);
    }

    function updateTarget(uint24 id, uint200 target) external onlyRole(GOVERNANCE_ROLE) {
        StakingPool storage pool = stakingPools[id];

        int200 d = _calculateDivergence(pool.balance, target);
        stakingPoolTree.updateDivergence(id, d);
        pool.target = target;
    }

    function setFee(uint256 _fee) external onlyRole(GOVERNANCE_ROLE) {
        if (_fee > MAX_FEE) revert();
        fee = _fee;
    }

    function validatorCount() external view returns (uint256) {
        return stakingPoolTree.getSize();
    }

    function previewUnwrap(uint256 shares) external view returns (address payable[] memory tenderizers, uint256[] memory amounts) {
        if (shares > totalSupply()) revert();
        uint256 amount = shares.mulWad(exchangeRate);

        uint256 k = stakingPoolTree.getSize();
        uint256 maxDrawdown = (totalAssets - amount) / k;
        tenderizers = new address payable[](k);
        amounts = new uint256[](k);
        uint24 id = stakingPoolTree.getLast();
        uint256 remaining = amount;
        uint256 index = 0;

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                continue;
            }

            uint256 max = pool.balance - maxDrawdown;
            uint256 draw = max < remaining ? max : remaining;

            tenderizers[index] = pool.tToken;
            amounts[index] = draw;
            index++;
            remaining -= draw;
            if (remaining == 0) {
                break;
            }
            id = stakingPoolTree.findPredecessor(id);
        }

        // Resize arrays
        assembly {
            mstore(tenderizers, index)
            mstore(amounts, index)
        }
    }

    // Internal helper functions
    function _calculateDivergence(uint256 balance, uint256 target) internal pure returns (int200) {
        if (balance < target) {
            return -int200(uint200(target - balance));
        } else {
            return int200(uint200(balance - target));
        }
    }

    // Required by OpenZeppelin
    function _authorizeUpgrade(address) internal override onlyRole(UPGRADE_ROLE) { }

    // Handle native token receives
    receive() external payable {
        // Allow contract to receive native tokens
    }
}
