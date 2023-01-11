// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.4;

import { console2 } from "forge-std/console2.sol";
import { PRBTest } from "test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { Vault } from "core/vault/Vault.sol";

import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

contract VaultSetup is PRBTest, StdCheats {
  using ClonesWithImmutableArgs for address;

  MockERC20 internal asset;
  Vault internal vault;

  address internal validator = address(0xf00);

  function setUp() public {
    // setup test ERC20 token
    asset = new MockERC20("Foo", "FOO", 18);
    // setup implementation Vault
    // Clone it with args
    vault = Vault(address(new Vault()).clone(abi.encodePacked(address(this), asset, validator)));
  }
}

contract VaultTest is VaultSetup {
  function testMetaData() public {
    assertEq(vault.name(), string(abi.encodePacked("tender", asset.symbol(), " ", validator)));
    assertEq(vault.symbol(), string(abi.encodePacked("t", asset.symbol(), "_", validator)));
    assertEq(vault.decimals(), uint8(18));
  }
}
