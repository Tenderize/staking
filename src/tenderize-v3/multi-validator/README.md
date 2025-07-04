# Multi-Validator LST for Tenderize v3

This directory contains the implementation of Multi-Validator Liquid Staking Tokens (LSTs) for native tokens in the Tenderize v3 ecosystem.

## Overview

The Multi-Validator LST system enables users to stake native tokens (like ETH, SEI) across multiple validators simultaneously, providing:

- **Diversified staking**: Automatically distribute stakes across multiple validators
- **Optimized allocation**: Use AVL tree-based algorithms to maintain target validator weights
- **Native token support**: Work directly with native blockchain tokens (not ERC20 wrapped)
- **Liquid staking**: Receive transferable LST tokens representing staked positions
- **NFT-based unstaking**: Track unstaking positions with unique NFTs

## Architecture

### Core Components

1. **MultiValidatorLST.sol**: Main liquid staking contract
   - ERC20 token representing staked positions
   - Handles deposits, unstaking, and validator management
   - Uses AVL tree for efficient validator weight management
   - Integrates with tenderize-v3 Tenderizer contracts

2. **UnstakeNFT.sol**: NFT contract for unstaking positions
   - ERC721 tokens representing pending withdrawals
   - Contains metadata about unstaking requests
   - Renders SVG-based token images with position details

3. **Factory.sol**: Deployment factory for new LST instances
   - Creates new MultiValidatorLST contracts for different native tokens
   - Uses CREATE2 for deterministic addresses
   - Manages initialization and ownership

4. **FlashUnstake.sol**: Instant unstaking contract
   - Allows immediate exit from LST positions without waiting for unlock periods
   - Swaps unwrapped validator tokens through TenderSwap for immediate liquidity
   - Simple two-function interface: flashUnstake() and flashUnstakeQuote()

## Key Features

### Native Token Integration

Unlike the original multi-validator system that works with ERC20 tokens, this version:

- Uses `payable` functions and `msg.value` for deposits
- Handles native token transfers directly
- Works with tenderize-v3 adapters that support native staking

### Validator Management

- **bytes32 validator IDs**: Validators identified by 32-byte identifiers
- **Target weights**: Each validator has a target allocation weight
- **Dynamic rebalancing**: Deposits automatically flow to under-allocated validators
- **AVL tree optimization**: Efficient validator selection and weight tracking

### Staking Flow

1. **Deposit**: Users send native tokens, receive LST tokens
2. **Distribution**: Funds automatically distributed across validators based on divergence
3. **Rewards**: Validator rewards compound into the exchange rate
4. **Unstaking**: Users burn LST tokens, receive unstaking NFT
5. **Withdrawal**: After unlock period, users redeem NFT for native tokens

## Usage Example

```solidity
// Deploy a new MultiValidatorLST for SEI network
string memory tokenSymbol = "SEI";
address lstAddress = factory.deploy(tokenSymbol);
MultiValidatorLST lst = MultiValidatorLST(payable(lstAddress));

// Add validators (governance only)
bytes32 validator1 = 0x1234...;
address tenderizer1 = 0x5678...;
uint200 targetWeight = 1000000; // 1M native tokens
lst.addValidator(validator1, tenderizer1, targetWeight);

// User deposits
uint256 shares = lst.deposit{value: 10 ether}(userAddress);

// User unstakes
uint256 unstakeId = lst.unstake(shares, minAmount);

// User withdraws after unlock period
uint256 amount = lst.withdraw(unstakeId);

// Flash unstake through TenderSwap for immediate liquidity
FlashUnstake flashUnstake = FlashUnstake(flashUnstakeAddress);
(uint256 nativeOut, uint256 fees) = flashUnstake.flashUnstake(
    address(lst),
    tenderSwapAddress,
    shares,
    minNativeOut
);
```

## Technical Details

### Exchange Rate Mechanism

The exchange rate between native tokens and LST tokens:

- Starts at 1:1 (1e18)
- Increases as validator rewards accrue
- Updated through `claimValidatorRewards()` calls
- Fees taken on rewards (configurable, max 10%)

### Validator Selection Algorithm

Deposits are distributed using:

1. Calculate divergence for each validator (current vs target weight)
2. Fill negative divergence validators first (under-allocated)
3. For large deposits, also allocate to least positive divergence validators
4. Maintain balanced allocation across validator set

### Unstaking Process

1. User calls `unstake(shares, minAmount)`
2. Shares burned immediately
3. Proportional amounts unstaked from validators
4. Unstaking NFT minted with position details
5. After unlock period, user calls `withdraw(unstakeId)`

### Flash Unstaking Process

For immediate liquidity without waiting for unlock periods:

1. User calls `flashUnstake(lst, tenderSwap, amount, minOut)`
2. LST tokens unwrapped to validator positions (individual tenderizer tokens)
3. Validator tokens approved and swapped through TenderSwap for native tokens
4. Native tokens returned immediately to user

## Security Features

- **Access Control**: Role-based permissions (GOVERNANCE, UPGRADE, MINTER)
- **Reentrancy Protection**: NonReentrant modifiers on state-changing functions
- **Upgrade Safety**: UUPS proxy pattern with role-based upgrade authorization
- **Native Token Safety**: Proper handling of native token transfers and failures

## Integration with Tenderize v3

This system integrates seamlessly with:

- **Tenderizer contracts**: Handle individual validator staking
- **Adapter pattern**: Support for different networks (Sei, Ethereum, etc.)
- **Registry system**: Centralized configuration and fee management
- **Unlock system**: Standardized unstaking periods across networks

## Deployment

The system is deployed through the Factory contract:

```solidity
Registry registry = Registry(0x...);
MultiValidatorFactory factory = new MultiValidatorFactory(registry);
factory.initialize();

// Deploy for specific token
address seiLST = factory.deploy("SEI");
address ethLST = factory.deploy("ETH");
```

## Governance

Key governance functions:

- `addValidator()`: Add new validators with target weights
- `removeValidator()`: Remove validators (only when balance is zero)
- `updateTarget()`: Modify target allocations
- `setFee()`: Adjust protocol fees (max 10%)

All governance functions require the `GOVERNANCE_ROLE` and follow a multi-sig approach through the Registry treasury.

## Files

- `MultiValidatorLST.sol` - Main LST contract (520 lines)
- `UnstakeNFT.sol` - Unstaking NFT contract (125 lines)  
- `Factory.sol` - Deployment factory (106 lines)
- `FlashUnstake.sol` - Instant unstaking contract (103 lines)
- `README.md` - This documentation

## Dependencies

- OpenZeppelin Contracts (Upgradeable)
- Solady (ERC20, Math, Utils)
- Tenderize Core (Registry, Adapters, AVL Tree)

## Testing

See the test files in `/test/tenderize-v3/multi-validator/` for comprehensive test coverage including:

- Deposit and unstaking flows
- Validator management
- Fee calculation
- Edge cases and error conditions
