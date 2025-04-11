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
    function deposit(address receiver, uint256 assets) external returns (uint256 shares) {
        // Transfer assets from sender
        token.safeTransferFrom(msg.sender, address(this), assets);

        // Stake assets
        uint24 count = 3;

        (, uint24 positiveNodes, uint24 negativeNodes,, int200 negDivergence) = stakingPoolTree.getTreeStats();

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
            uint24 maxCount = negativeNodes > count ? count : negativeNodes;
            (uint24[] memory validatorIDs,) = stakingPoolTree.findMostDivergent(false, maxCount);
            uint256[] memory depositAmounts = new uint256[](maxCount);
            for (uint24 i = 0; i < maxCount; i++) {
                StakingPool storage pool = stakingPools[validatorIDs[i]];
                depositAmounts[i] = pool.target - pool.balance;
            }

            // Fill the remaining between a set of validators all above surplus, start with the one least in surplus
            maxCount = positiveNodes > count ? count : positiveNodes;
            (validatorIDs,) = stakingPoolTree.findMostDivergent(false, maxCount);
            StakingPool[] memory items = new StakingPool[](maxCount);

            for (uint24 i = 0; i < maxCount; i++) {
                StakingPool storage pool = stakingPools[validatorIDs[i]];
                items[i] = StakingPool(pool.tToken, pool.target, pool.balance);

                // IN THEORY: This set should all have positive divergence, so we can use the absolute values
                // instead of the signed integers.
                totalDivergence += int200(int256((pool.balance - pool.target)));
            }

            for (uint24 i = 0; i < maxCount; i++) {
                int256 div = int256(items[i].target - items[i].balance);
                int256 amount = int256(depositAmounts[i] + assets);
                amount = amount * div / int256(totalDivergence);
                ERC20(token).approve(items[i].tToken, uint256(amount));
                uint256 tTokens = Tenderizer(items[i].tToken).deposit(address(this), uint256(amount));
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
        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                continue;
            }
            uint256 max = pool.balance - maxDrawdown; // Edge case with rounding
            uint256 draw = max < remaining ? max : remaining;
            tTokens[i] = pool.tToken;
            amounts[i] = draw;
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
            id = nextId;
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

        for (uint256 i = 0; i < k; i++) {
            StakingPool storage pool = stakingPools[id];
            if (maxDrawdown >= pool.balance) {
                id = stakingPoolTree.findPredecessor(id);
                continue;
            }
            uint256 max = pool.balance - maxDrawdown; // Edge case with rounding
            uint256 draw = max < remaining ? max : remaining;
            tTokens[i] = pool.tToken;
            amounts[i] = draw;
            if (draw == remaining) {
                break;
            }
            remaining -= draw;
            id = stakingPoolTree.findPredecessor(id);
        }
    }

    // TODO: Allow governance to execute a series of transaction to rebalance
    // The contract. This could be e.g. staking, unstaking or withdraw operations, or even a tenderswap call.
    function rebalance(
        address[] calldata targets,
        bytes[] calldata datas,
        uint256[] calldata values
    )
        external
        onlyRole(GOVERNANCE_ROLE)
    {
        uint256 l = targets.length;
        for (uint256 i = 0; i < l; i++) {
            (bool success,) = targets[i].call{ value: values[i] }(datas[i]);
            if (!success) revert RebalanceFailed(targets[i], datas[i], values[i]);
        }
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
}
