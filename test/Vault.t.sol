// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { console2 } from "forge-std/console2.sol";
import { PRBTest } from "test/PRBTest.sol";
import { StdCheats } from "forge-std/StdCheats.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { Vault } from "core/vault/Vault.sol";
import { IVault } from "core/vault/IVault.sol";

import { ClonesWithImmutableArgs } from "clones/ClonesWithImmutableArgs.sol";

contract TestHelpers {
  function mintTokens(MockERC20 token, address to, uint256 amount) public {
    token.mint(to, amount);
  }

  function sqrt(uint256 a) public pure returns (uint256) {
    uint256 x = a;
    uint256 y = (a + 1) / 2;
    while (x > y) {
      x = y;
      y = (x + a / x) / 2;
    }
    return x;
  }
}

contract VaultSetup is TestHelpers, PRBTest, StdCheats, IVault {
  using ClonesWithImmutableArgs for address;

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

// solhint-disable func-name-mixedcase
contract VaultTest is VaultSetup {
  address private account0 = vm.addr(0x01);
  address private account1 = vm.addr(0x02);

  function test_Vault_ImmutableArgs() public {
    assertEq(vault.owner(), address(this));
    assertEq(vault.asset(), address(asset));
    assertEq(vault.validator(), validator);
  }

  function test_Vault_Metadata() public {
    assertEq(vault.name(), string(abi.encodePacked("tender", asset.symbol(), " ", validator)));
    assertEq(vault.symbol(), string(abi.encodePacked("t", asset.symbol(), "_", validator)));
    assertEq(vault.decimals(), uint8(18));
  }

  function test_Vault_InitialState() public {
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalShares(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.balanceOf(account0), 0);
    assertEq(vault.allowance(account0, account1), 0);
    assertEq(vault.nonces(account0), 0);
    assertEq(vault.convertToAssets(100), 100);
    assertEq(vault.convertToShares(100), 100);
  }

  function test_Vault_Deposit_OnlyOwner() public {
    vm.expectRevert(abi.encodeWithSelector(IVault.OnlyOwner.selector, address(this), account0));
    vm.prank(account0);
    vault.deposit(account0, 1);
  }

  function test_Vault_Deposit_ZeroSharesError() public {
    vm.expectRevert(abi.encodePacked(IVault.ZeroShares.selector));
    vault.deposit(address(this), 0);
  }

  function test_Vault_Deposit_InsufficientBalance(uint256 assets) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vm.expectRevert(abi.encodePacked("TRANSFER_FROM_FAILED"));
    vault.deposit(address(this), assets + 1);
  }

  function test_Vault_Deposit(uint256 assets) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));
    assets = 1;
    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    assertEq(vault.totalAssets(), assets);
    assertEq(vault.totalShares(), assets);
    assertEq(vault.totalSupply(), assets);
    assertEq(vault.balanceOf(address(this)), assets);
    assertEq(vault.convertToAssets(assets), assets);
    assertEq(vault.convertToShares(assets), assets);
  }

  function test_Vault_Deposit_MultipleUsers(uint256 assets, uint256 assets2) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));
    vm.assume(assets2 > 0 && assets2 < sqrt(type(uint256).max - 1));

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    assertEq(vault.totalAssets(), assets);
    assertEq(vault.totalShares(), assets);
    assertEq(vault.totalSupply(), assets);
    assertEq(vault.balanceOf(address(this)), assets);
    assertEq(vault.convertToAssets(assets), assets);
    assertEq(vault.convertToShares(assets), assets);

    mintTokens(asset, address(this), assets2);
    asset.approve(address(vault), assets2);
    vault.deposit(address(this), assets2);
    assertEq(vault.totalAssets(), assets + assets2);
    assertEq(vault.totalShares(), assets + assets2);
    assertEq(vault.totalSupply(), assets + assets2);
    assertEq(vault.balanceOf(address(this)), assets + assets2);
    assertEq(vault.convertToAssets(assets + assets2), assets + assets2);
    assertEq(vault.convertToShares(assets + assets2), assets + assets2);
  }

  function test_Vault_Unlock_OnlyOwner() public {
    vm.expectRevert(abi.encodeWithSelector(IVault.OnlyOwner.selector, address(this), account0));
    vm.prank(account0);
    vault.unlock(account0, 1);
  }

  function test_Vault_Unlock_ZeroShares() public {
    vm.expectRevert(abi.encodePacked(IVault.ZeroShares.selector));
    vault.unlock(address(this), 0);
  }

  function test_Vault_Unlock_InsufficientBalance(uint256 assets) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    // underflow
    vm.expectRevert();
    vault.unlock(address(this), assets + 1);
  }

  function test_Vault_Unlock(uint256 assets) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    vault.unlock(address(this), assets);
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalShares(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.balanceOf(address(this)), 0);
    assertEq(vault.convertToAssets(0), 0);
    assertEq(vault.convertToShares(0), 0);
  }

  function test_Vault_Unlock_Partial(uint256 assets, uint256 unlock) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));
    vm.assume(unlock > 0 && unlock < assets);

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    vault.unlock(address(this), unlock);
    assertEq(vault.totalAssets(), assets - unlock);
    assertEq(vault.totalShares(), assets - unlock);
    assertEq(vault.totalSupply(), assets - unlock);
    assertEq(vault.balanceOf(address(this)), assets - unlock);
    assertEq(vault.convertToAssets(assets - unlock), assets - unlock);
    assertEq(vault.convertToShares(assets - unlock), assets - unlock);
  }

  function test_Vault_Unlock_MultipleUsers(uint256 assets, uint256 assets2) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));
    vm.assume(assets2 > 0 && assets2 < sqrt(type(uint256).max - 1));

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    mintTokens(asset, address(this), assets2);
    asset.approve(address(vault), assets2);
    vault.deposit(address(this), assets2);
    vault.unlock(address(this), assets);
    assertEq(vault.totalAssets(), assets2);
    assertEq(vault.totalShares(), assets2);
    assertEq(vault.totalSupply(), assets2);
    assertEq(vault.balanceOf(address(this)), assets2);
    assertEq(vault.convertToAssets(assets2), assets2);
    assertEq(vault.convertToShares(assets2), assets2);

    // unlock assets2
    vault.unlock(address(this), assets2);
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalShares(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.balanceOf(address(this)), 0);
  }

  function test_Vault_Unlock_MultipleUsers_Partial(uint256 assets, uint256 assets2, uint256 unlock) public {
    vm.assume(assets > 0 && assets < sqrt(type(uint256).max - 1));
    vm.assume(assets2 > 0 && assets2 < sqrt(type(uint256).max - 1));
    vm.assume(unlock > 0 && unlock < assets);

    mintTokens(asset, address(this), assets);
    asset.approve(address(vault), assets);
    vault.deposit(address(this), assets);
    mintTokens(asset, address(this), assets2);
    asset.approve(address(vault), assets2);
    vault.deposit(address(this), assets2);
    vault.unlock(address(this), unlock);
    assertEq(vault.totalAssets(), assets + assets2 - unlock);
    assertEq(vault.totalShares(), assets + assets2 - unlock);
    assertEq(vault.totalSupply(), assets + assets2 - unlock);
    assertEq(vault.balanceOf(address(this)), assets + assets2 - unlock);
    assertEq(vault.convertToAssets(assets + assets2 - unlock), assets + assets2 - unlock);
    assertEq(vault.convertToShares(assets + assets2 - unlock), assets + assets2 - unlock);
  }
}
