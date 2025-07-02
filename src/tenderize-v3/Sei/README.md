# Sei Network Adapter

This directory contains the Tenderizer adapter implementation for the Sei Network, enabling liquid staking functionality for SEI tokens.

## Overview

The Sei adapter integrates with Sei's native staking precompile to provide delegation, undelegation, and withdrawal functionality through the Tenderizer protocol. The adapter converts `bytes32` validator identifiers to Sei bech32 validator addresses automatically.

## Files

- `Sei.sol` - Contains the interface definitions for the Sei staking precompile and related structs
- `SeiAdapter.sol` - The main adapter implementation that conforms to the Tenderizer Adapter interface

## Key Features

### Address Conversion

- Sei validators use bech32-encoded addresses (e.g., "seivaloper1abc123...")
- Tenderizer uses `bytes32` validator identifiers
- The adapter automatically converts `bytes32` to Sei validator addresses using bech32 encoding
- Takes the first 20 bytes from `bytes32` and encodes with "seivaloper" prefix

### Precision Handling

- Sei uses 6 decimal precision (1 SEI = 1,000,000 uSEI)
- Ethereum/Tenderizer uses 18 decimal precision
- The adapter automatically handles conversion between the two formats

### Staking Operations

#### Delegation (`stake`)

- Delegates SEI tokens to a specified validator
- Converts amounts from 18 to 6 decimal precision
- Uses Sei's staking precompile for the actual delegation

#### Undelegation (`unstake`)

- Initiates undelegation from a validator
- Creates an unlock record with a 21-day unbonding period
- Returns an unlock ID for tracking the undelegation

#### Withdrawal (`withdraw`)

- Allows withdrawal of undelegated tokens after the unbonding period
- Validates that the unbonding period has elapsed
- Cleans up unlock records after successful withdrawal

#### Rebalancing (`rebase`)

- Queries current delegation amounts from Sei
- Converts balances back to 18 decimal precision
- Enables accurate tracking of staking rewards

## Usage

### 1. Deploy the Adapter

```solidity
SeiAdapter adapter = new SeiAdapter();
```

### 2. Stake Tokens (validators are automatically converted)

```solidity
bytes32 validatorId = hex"1234567890abcdef1234567890abcdef12345678000000000000000000000000";
uint256 amount = 1 ether; // 18 decimal precision
uint256 staked = adapter.stake(validatorId, amount);
```

### 3. Unstake Tokens

```solidity
uint256 unlockId = adapter.unstake(validatorId, amount);
```

### 4. Withdraw After Unbonding

```solidity
// Wait for 21 days, then:
uint256 withdrawn = adapter.withdraw(validatorId, unlockId);
```

## Address Conversion Details

The adapter uses the following process to convert `bytes32` to Sei validator addresses:

1. Extract the first 20 bytes from the `bytes32` validator ID
2. Encode using bech32 with "seivaloper" human-readable prefix
3. The resulting address format: `seivaloper{bech32_encoded_data}`

Example:

- Input: `0x1234567890abcdef1234567890abcdef12345678000000000000000000000000`
- Output: `seivaloper{bech32_encoded_20_bytes}`

## Constants

- `SEI_STAKING_PRECOMPILE_ADDRESS`: `0x0000000000000000000000000000000000001005`
- `PRECISION_SCALE`: `1e12` (conversion factor between 18 and 6 decimals)
- `UNBONDING_PERIOD`: `21 days` (Sei's unbonding period)

## Error Handling

The adapter includes several custom errors:

- `UnlockNotReady`: Attempted withdrawal before unbonding period completion
- `DelegationFailed`: Sei staking precompile delegation call failed
- `UndelegationFailed`: Sei staking precompile undelegation call failed
- `InvalidAmount`: Zero or invalid amount provided
- `Bech32DecodeError`: Error in bech32 encoding/decoding process

## Testing

Comprehensive tests are available in `test/adapters/SeiAdapter.t.sol` including:

- Basic functionality tests
- Error condition handling
- Mock Sei precompile for isolated testing
- Multiple unlock scenario testing
- Bech32 conversion testing

## Integration with Tenderizer

This adapter is designed to work seamlessly with the Tenderizer protocol, providing:

- ERC165 interface compliance
- Proper adapter interface implementation
- Native asset support (as opposed to ERC20 tokens)
- Beacon chain compatibility
- Automatic address conversion without external dependencies

The adapter enables users to stake SEI tokens through Tenderizer and receive liquid staking tokens in return, while maintaining the ability to unstake and withdraw their original SEI tokens after the unbonding period. No validator registration is required - the adapter automatically converts validator identifiers to the appropriate Sei addresses.
