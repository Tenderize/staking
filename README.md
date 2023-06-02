# Tenderize - Liquid Native Staking

The Tenderize protocol enables **liquid native staking**, each validator on a network can have its own permissionless liquid staking vault and ERC20 token for itself and its delegators. It is designed to be fully credibly neutral and autonomous, while enabling more flexibility to users when staking.

## What's Inside

- [TenderToken](https://github.com/paulrberg/prb-test): modern collection of testing assertions and logging utilities
- [Tenderizer](https://github.com/foundry-rs/foundry/blob/master/forge): compile, test, fuzz, debug and deploy smart
  contracts
- [Unlocks](https://github.com/foundry-rs/forge-std): collection of helpful contracts and cheatcodes for testing
- [Adapters](https://github.com/protofire/solhint): code linter
- [Registry](https://github.com/prettier-solidity/prettier-plugin-solidity): code formatter
- [Factory]()

### TenderToken

### Tenderizer

## Getting Started

## Usage

Here's a list of the most frequently needed commands.

### Build

Build the contracts:

```sh
forge build
```

### Clean

Delete the build artifacts and cache directories:

```sh
forge clean
```

### Compile

Compile the contracts:

```sh
forge build
```

### Coverage

Get a test coverage report:

```sh
forge coverage
```

### Deploy

Deploy to Anvil:

```sh
$ forge script script/Foo.s.sol:FooScript --fork-url http://localhost:8545 \
 --broadcast --private-key $PRIVATE_KEY
```

For instructions on how to deploy to a testnet or mainnet, check out the
[Solidity Scripting tutorial](https://book.getfoundry.sh/tutorials/solidity-scripting.html).

### Format

Format the contracts:

```sh
forge fmt
```

### Gas Usage

Get a gas report:

```sh
forge test --gas-report
```

### Lint

Lint the contracts:

```sh
yarn lint
```

### Test

Run the tests:

```sh
forge test
```

## Notes

1. Foundry piggybacks off [git submodules](https://git-scm.com/book/en/v2/Git-Tools-Submodules) to manage dependencies.
   There's a [guide](https://book.getfoundry.sh/projects/dependencies.html) about how to work with dependencies in the
   book.
2. You don't have to create a `.env` file, but filling in the environment variables may be useful when debugging and
   testing against a mainnet fork.
