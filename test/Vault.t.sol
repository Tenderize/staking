// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.17;

// import { console2 } from "forge-std/console2.sol";
// import { PRBTest } from "test/PRBTest.sol";
// import { StdCheats } from "forge-std/StdCheats.sol";
// import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
// import { Vault } from "core/vault/Vault.sol";
// import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

// contract TestHelpers {
//   function mintTokens(MockERC20 token, address to, uint256 amount) public {
//     token.mint(to, amount);
//   }

//   function sqrt(uint256 a) public pure returns (uint256) {
//     uint256 x = a;
//     uint256 y = (a + 1) / 2;
//     while (x > y) {
//       x = y;
//       y = (x + a / x) / 2;
//     }
//     return x;
//   }
// }

// contract VaultSetup is TestHelpers, PRBTest, StdCheats {
//   using ClonesWithImmutableArgs for address;

//   // TODO: move events to interface
//   event Deposit(address indexed sender, address indexed receiver, uint256 assets);
//   event Unlock(address indexed receiver, uint256 assets);
//   event Withdraw(address indexed receiver, uint256 assets);

//   MockERC20 internal asset;
//   Vault internal vault;

//   address internal validator = vm.addr(0xf00);

//   function setUp() public {
//     // setup test ERC20 token
//     asset = new MockERC20("Foo", "FOO", 18);
//     // setup implementation Vault
//     // Clone it with args
//     vault = Vault(address(new Vault()).clone(abi.encodePacked(asset, validator)));
//   }
// }

// // solhint-disable func-name-mixedcase
// contract VaultTest is VaultSetup {
//   address private account0 = vm.addr(0x01);
//   address private account1 = vm.addr(0x02);

//   function test_Vault_ImmutableArgs() public {
//     assertEq(vault.asset(), address(asset));
//     assertEq(vault.validator(), validator);
//   }

//   function test_Vault_Metadata() public {
//     assertEq(vault.name(), string(abi.encodePacked("tender", asset.symbol(), " ", validator)));
//     assertEq(vault.symbol(), string(abi.encodePacked("t", asset.symbol(), "_", validator)));
//     assertEq(vault.decimals(), uint8(18));
//   }

//   function test_Vault_InitialState() public {
//     assertEq(vault.totalAssets(), 0);
//     assertEq(vault.totalShares(), 0);
//     assertEq(vault.totalSupply(), 0);
//     assertEq(vault.balanceOf(account0), 0);
//     assertEq(vault.allowance(account0, account1), 0);
//     assertEq(vault.nonces(account0), 0);
//     assertEq(vault.convertToAssets(100), 100);
//     assertEq(vault.convertToShares(100), 100);
//   }
// }
