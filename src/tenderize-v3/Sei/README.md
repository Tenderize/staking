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

## Addresses

### Testnet (atlantic-2)

forge script script/Tenderize_Native_Deploy.s.sol --broadcast -vvv --private-key $PRIVKEY --rpc-url $RPC_URL --skip-simulation

ASSET=0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE REGISTRY=0x4EB2ce452ea35A050495c3c23193b385f48473C0 forge script script/Adapter_Deploy.s.sol --broadcast --private-key $PRIVKEY --rpc-url $RPC_URL --skip-simulation

REGISTRY=0x4EB2ce452ea35A050495c3c23193b385f48473C0 cast send --private-key $PRIVKEY --rpc-url $RPC_URL $REGISTRY "registerAdapter(address,address)" 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE 0xa60Af847e4BE2bC48F878F69FC436ba018206041

cast call --rpc-url $RPC_URL $ADAPTER "validatorStringToBytes32(string)" seivaloper1xtf2jmastk0tejjqrhc9ax48qsvvkd92s6pg4u

cast call --rpc-url $RPC_URL $ADAPTER "bytes32ToValidatorString(bytes32)" 0x2af815558b165be177531446f693fb7e7f3563e1000000000000000000000000

cast send --private-key $PRIVKEY --rpc-url $RPC_URL $FACTORY "createTenderizer(address,bytes32)" 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE 0x2af815558b165be177531446f693fb7e7f3563e1000000000000000000000000

  Registry Implementation:  0xF813ef59B3C34C63faf91602aEe609338e783FCC
  Registry Proxy:  0x50d9655930e1b6Bc543Ecbe650F166D1389c3E1C
  Renderer Implementation:  0x4C8c577198944971098C9076F05d9D6964Fe8be8
  Renderer Proxy:  0x2e51d396ec083D0bc67Ef7FBaACb57CF8354a690
  Unlocks:  0xF770fe8db9B6d52A23594B6f89bB798Da38c3586
  Tenderizer Implementation:  0x10Ad72B355245cEA919ae7B7C0962B5875e6ddDB
  Factory (Beacon):  0xb0E174D9235f133333c71bB47120e4Cb26442386

  SwapFactory deployed at:  0x2351fd85C1f9c81Cb6802A338017271779c0ddba
  Implementation deployed at:  0x06594dFF3436eBd36264191CaB0FaD20b78CB57f
  
  TenderSwap deployed at:  0x5c57F4E063a2A1302D78ac9ec2C902ec621200d3
  Implementation deployed at:  0xeF0e582A07E5a02b36B2c834C98b161E2915a585

  seivaloper19tup24vtzed7za6nz3r0dylm0eln2clpvhtawu -- 0x2af815558b165be177531446f693fb7e7f3563e1000000000000000000000000 -- 0x0BA49e1b6616CCb0650B39043554ad791b1b6eD1

  seivaloper1xtf2jmastk0tejjqrhc9ax48qsvvkd92s6pg4u -- 0x32d2a96fb05d9ebcca401df05e9aa70418cb34aa000000000000000000000000 -- 0xCF4cD036Ac6FAB8F6bd49C0890ed53a38767B62F

  seivaloper1sq7x0r2mf3gvwr2l9amtlye0yd3c6dqa4th95v -- 0x803c678d5b4c50c70d5f2f76bf932f23638d341d000000000000000000000000 -- 0x06fd675BE0513d4fF5F05796a3BAD9d20d91610B

  seivaloper13zp8kx7kux2wstxk7qyjk89npmuwlat090ru4w -- 0x88827b1bd6e194e82cd6f0092b1cb30ef8eff56f000000000000000000000000 -- 0x82c72F3Aefc525ade379b6E71E23f71e8fe84aab

  seivaloper15lu2zzp9ll0x6weth0y0wr3ur7rd4f933qefty -- 0xa7f8a10825ffde6d3b2bbbc8f70e3c1f86daa4b1000000000000000000000000 -- 0xb1bFDC5C304BC9212964C27D499Ea80F7D0a6E5A

cast send --private-key $PRIVKEY --rpc-url $RPC_URL --value 4000000000000000 0x58CDD57FD0c878AF54eD0D9578959BA8FD154Aa7 "deposit(address)" 0xd45E4347b33FA87C466ebA5E32823D76BaCC7eD7

cast call 0x0000000000000000000000000000000000001005 "delegation(address,string)" 0x0BA49e1b6616CCb0650B39043554ad791b1b6eD1 "seivaloper19tup24vtzed7za6nz3r0dylm0eln2clpvhtawu"

cast send --private-key $PRIVKEY --rpc-url $RPC_URL --value 2000000000000000000 0x9718b28CddDb84B941bEf97Eb9e4fbe32dc90152 "deposit(uint256)" 1900000000000000000

cast call --rpc-url $RPC_URL 0x5c57F4E063a2A1302D78ac9ec2C902ec621200d3 "quote(address,uint256)" 0x28D5bC07301472829bab14aC26CF74676e9FB1d3 100000000000000

cast send  --private-key $PRIVKEY --rpc-url $RPC_URL 0x50d9655930e1b6Bc543Ecbe650F166D1389c3E1C "setTreasury(address)" 0xd45E4347b33FA87C466ebA5E32823D76BaCC7eD7

REGISTRY=0x50d9655930e1b6Bc543Ecbe650F166D1389c3E1C forge script script/multi-validator/MultiValidatorFactory.native.deploy.s.sol --broadcast -vvv --private-key $PRIVKEY --rpc-url $RPC_URL --skip-simulation

FACTORY=0xce48304A0c94eC79a5f8ca9Fc3Aa8498382711E6 forge script script/multi-validator/MultiValidatorLST.native.deploy.s.sol --broadcast -vvvv --private-key $PRIVKEY --rpc-url $RPC_URL --skip-simulation

  MultiValidatorFactory deployed at: 0xce48304A0c94eC79a5f8ca9Fc3Aa8498382711E6
  FlashUnstake deployed at: 0xce48304A0c94eC79a5f8ca9Fc3Aa8498382711E6

  tSEI deployed at: 0x0027305D78Accd068d886ac4217B67922E9F490f

cast send --private-key $PRIVKEY --rpc-url $RPC_URL --value 1000000000000000000 0x82c72f3aefc525ade379b6e71e23f71e8fe84aab "rebase()

cast call --rpc-url $RPC_URL 0x0000000000000000000000000000000000001005 "delegation(address,string)" 0x82c72F3Aefc525ade379b6E71E23f71e8fe84aab "seivaloper13zp8kx7kux2wstxk7qyjk89npmuwlat090ru4w"

cast call --rpc-url $RPC_URL 0x82c72F3Aefc525ade379b6E71E23f71e8fe84aab "totalSupply()"
