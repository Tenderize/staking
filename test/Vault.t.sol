// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";
import { PRBTest } from "test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { Vault } from "core/vault/Vault.sol";

import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

// solhint-disable func-name-mixedcase

contract TestHelpers {
  function mintTokens(
    MockERC20 token,
    address to,
    uint256 amount
  ) public {
    token.mint(to, amount);
  }
}

contract VaultSetup is TestHelpers, PRBTest, StdCheats {
  using ClonesWithImmutableArgs for address;

  // TODO: move events to interface
  event Deposit(address indexed sender, address indexed receiver, uint256 assets);

  MockERC20 internal asset;
  Vault internal vault;

  address internal validator = vm.addr(0xf00);

  function setUp() public {
    // setup test ERC20 token
    asset = new MockERC20("Foo", "FOO", 18);
    // setup implementation Vault
    // Clone it with args
    vault = Vault(address(new Vault()).clone(abi.encodePacked(address(this), asset, validator)));
  }
}

contract VaultTest is VaultSetup {
  address private account0 = vm.addr(0x01);
  address private account1 = vm.addr(0x02);

  function testImmutableArgs() public {
    assertEq(vault.owner(), address(this));
    assertEq(vault.asset(), address(asset));
    assertEq(vault.validator(), validator);
  }

  function testMetadata() public {
    assertEq(vault.name(), string(abi.encodePacked("tender", asset.symbol(), " ", validator)));
    assertEq(vault.symbol(), string(abi.encodePacked("t", asset.symbol(), "_", validator)));
    assertEq(vault.decimals(), uint8(18));
  }

  function testInitialState() public {
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalShares(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.balanceOf(account0), 0);
    assertEq(vault.allowance(account0, account1), 0);
    assertEq(vault.nonces(account0), 0);
    assertEq(vault.convertToAssets(100), 100);
    assertEq(vault.convertToShares(100), 100);
  }

  function testDeposit_ZeroShares_Error() public {
    vm.expectRevert(abi.encodeWithSelector(Vault.ZeroShares.selector));
    vault.deposit(0, address(this), address(this));
  }

  function testDeposit_Success(uint256 amount) public {
    vm.assume(amount != 0);
    vm.assume(amount < 10e27);

    // check for event
    vm.expectEmit(true, true, true, false);
    emit Deposit(validator, validator, amount);

    // from validator
    mintTokens(asset, validator, amount);
    vm.prank(validator);
    asset.approve(address(vault), amount);
    vault.deposit(amount, validator, validator);

    assertEq(vault.balanceOf(validator), amount);
    assertEq(vault.totalAssets(), amount);
    assertEq(vault.totalShares(), amount);
    assertEq(vault.totalSupply(), amount);
  }
}
