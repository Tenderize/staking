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
  uint256 MAX_INT_SQRT = 340282366920938463463374607431768211455;

  error ZeroAmount();
  event Deposit(address indexed sender, address indexed receiver, uint256 assets);

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

  function testInitiailState() public {
    assertEq(vault.totalAssets(), 0);
    assertEq(vault.totalShares(), 0);
    assertEq(vault.totalSupply(), 0);
    assertEq(vault.balanceOf(address(0xBEEF)), 0);
    assertEq(vault.allowance(address(0xBEEF), address(0xABCD)), 0);
    assertEq(vault.nonces(address(0xBEEF)), 0);
    assertEq(vault.convertToAssets(100), 0);
    assertEq(vault.convertToShares(100), 100);
  }

  // Deposit

  function testDepositRevertsWithZeroAmount() public {
    vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
    vault.deposit(0, address(this), address(this));
  }

  function _depositPreReq(uint256 depositAmount) public {
    vm.assume(depositAmount > 0);
    vm.assume(depositAmount < MAX_INT_SQRT);
    asset.mint(address(this), depositAmount);
    asset.approve(address(vault), depositAmount);
  }

  function testDepositTransfersAssets(uint256 depositAmount) public {
    _depositPreReq(depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
    assertEq(asset.balanceOf(address(vault)), depositAmount);
  }

  function testDepositMintsTenderTokens(uint256 depositAmount) public {
    _depositPreReq(depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
    assertEq(vault.balanceOf(address(this)), depositAmount);
  }

  function testDepositEmitsEvent(uint256 depositAmount) public {
    _depositPreReq(depositAmount);
    vm.expectEmit(true, true, true, false);
    emit Deposit(address(this), address(this), depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
  }
}
