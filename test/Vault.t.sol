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

  // TODO: Get from Vault Contract
  error ZeroAmount();
  error ZeroShares();
  event Deposit(address indexed sender, address indexed receiver, uint256 assets);
  event Unlock(address indexed sender, uint256 indexed assets);
  event Withdraw(address indexed receiver, uint256 assets);
  event Rebase(uint256 newTotalAssets, uint256 oldTotalAssets);

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
    assertEq(vault.convertToAssets(100), 100);
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

  function testDepositIncreasesAssets(uint256 depositAmount) public {
    _depositPreReq(depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
    assertEq(vault.totalAssets(), depositAmount);
  }

  function testDepositEmitsEvent(uint256 depositAmount) public {
    _depositPreReq(depositAmount);
    vm.expectEmit(true, true, true, false);
    emit Deposit(address(this), address(this), depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
  }

  // Unlock

  function testUnlockRevertsWithZeroAmount() public {
    vm.expectRevert(abi.encodeWithSelector(ZeroShares.selector));
    vault.unlock(0, address(this));
  }

  function testUnlockRevertsIfZeroShares() public {
    vm.expectRevert();
    vault.unlock(100, address(this));
  }

  function _unlockPreReq(uint256 depositAmount, uint256 unlockAmount) internal {
    vm.assume(depositAmount > unlockAmount);
    vm.assume(unlockAmount > 0);
    _depositPreReq(depositAmount);
    vault.deposit(depositAmount, address(this), address(this));
  }

  function testUnlockBurnsTenderTokens(uint256 depositAmount, uint256 unlockAmount) public {
    _unlockPreReq(depositAmount, unlockAmount);
    vault.unlock(unlockAmount, address(this));
    assertEq(vault.balanceOf(address(this)), depositAmount - unlockAmount);
  }

  function testUnlockReducesAssets(uint256 depositAmount, uint256 unlockAmount) public {
    _unlockPreReq(depositAmount, unlockAmount);
    vault.unlock(unlockAmount, address(this));
    assertEq(vault.totalAssets(), depositAmount - unlockAmount);
  }

  function testUnlockEmits(uint256 depositAmount, uint256 unlockAmount) public {
    _unlockPreReq(depositAmount, unlockAmount);
    vm.expectEmit(true, true, true, false);
    emit Unlock(address(this), unlockAmount);
    vault.unlock(unlockAmount, address(this));
  }

  // Withdraw
  function testWithdrawRevertsWithZeroAmount() public {
    vm.expectRevert(abi.encodeWithSelector(ZeroAmount.selector));
    vault.withdraw(0, address(this));
  }

  function testWithdrawTransfersTokens(uint256 withdrawAmount) public {
    vm.assume(withdrawAmount > 0);
    // simulate transfer of tokens from underlying 
    asset.mint(address(vault), withdrawAmount);
    vault.withdraw(withdrawAmount, address(0xBEEF));
    assertEq(asset.balanceOf(address(0xBEEF)), withdrawAmount);
  }

  function testWithdrawEmitsEvent(uint256 withdrawAmount) public {
    vm.assume(withdrawAmount > 0);
    // simulate transfer of tokens from underlying 
    asset.mint(address(vault), withdrawAmount);
    vm.expectEmit(true, true, true, false);
    emit Withdraw(address(0xBEEF), withdrawAmount);
    vault.withdraw(withdrawAmount, address(0xBEEF));
  }

  // Rebase
  function testRebaseSetsNewTotalAssets(uint256 newTotalAssets) public {
    vault.rebase(newTotalAssets);
    assertEq(vault.totalAssets(), newTotalAssets);
  }

  function testRebaseEmitsEvent(uint256 newTotalAssets) public {
    emit Rebase(newTotalAssets, 0);
    vault.rebase(newTotalAssets);
  }
}
