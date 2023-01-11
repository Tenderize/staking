// SPDX-License-Identifier: MIT
//
//  _____              _           _
// |_   _|            | |         (_)
//   | | ___ _ __   __| | ___ _ __ _ _______
//   | |/ _ \ '_ \ / _` |/ _ \ '__| |_  / _ \
//   | |  __/ | | | (_| |  __/ |  | |/ /  __/
//   \_/\___|_| |_|\__,_|\___|_|  |_/___\___|
//
// Copyright (c) Tenderize Labs Ltd

pragma solidity 0.8.17;

import { IERC20 } from "core/interfaces/IERC20.sol";
import { TTokenStorage } from "core/tendertoken/TTokenStorage.sol";

/// @notice Non-standard ERC20 + EIP-2612 implementation.
/// @author Tenderize
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.

abstract contract TToken is TTokenStorage, IERC20 {
  bytes32 private constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  uint8 public constant DECIMALS = 18;

  function decimals() public pure returns (uint8) {
    return DECIMALS;
  }

  function name() public view virtual returns (string memory);

  function symbol() public view virtual returns (string memory);

  function convertToAssets(uint256 shares) public view virtual returns (uint256 assets);

  function convertToShares(uint256 assets) public view virtual returns (uint256 shares);

  function balanceOf(address account) public view virtual returns (uint256) {
    return convertToAssets(_loadERC20Slot().balanceOf[account]);
  }

  function totalSupply() public view virtual returns (uint256) {
    ERC20Data storage s = _loadERC20Slot();
    return convertToAssets(s._totalSupply);
  }

  function approve(address spender, uint256 amount) public virtual returns (bool) {
    ERC20Data storage s = _loadERC20Slot();
    s.allowance[msg.sender][spender] = amount;

    emit Approval(msg.sender, spender, amount);

    return true;
  }

  function transfer(address to, uint256 amount) public virtual returns (bool) {
    ERC20Data storage s = _loadERC20Slot();
    uint256 shares = convertToShares(amount);
    // underflows if insufficient balance
    s.balanceOf[msg.sender] -= shares;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value.
    unchecked {
      s.balanceOf[to] += shares;
    }

    emit Transfer(msg.sender, to, amount);

    return true;
  }

  function allowance(address owner, address spender) external view returns (uint256) {
    ERC20Data storage s = _loadERC20Slot();
    return s.allowance[owner][spender];
  }

  function nonces(address owner) external view returns (uint256) {
    ERC20Data storage s = _loadERC20Slot();
    return s.nonces[owner];
  }

  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) public virtual returns (bool) {
    ERC20Data storage s = _loadERC20Slot();
    uint256 allowed = s.allowance[from][msg.sender]; // Saves gas for limited approvals.

    if (allowed != type(uint256).max) {
      s.allowance[from][msg.sender] = allowed - amount;
    }

    uint256 shares = convertToShares(amount);

    s.balanceOf[from] -= shares;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value.
    unchecked {
      s.balanceOf[to] += shares;
    }

    emit Transfer(from, to, amount);

    return true;
  }

  function permit(
    address owner,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) public virtual {
    require(deadline >= block.timestamp, "PERMIT_DEADLINE_EXPIRED");

    // Unchecked because the only math done is incrementing
    // the owner's nonce which cannot realistically overflow.

    unchecked {
      address recoveredAddress = ecrecover(
        keccak256(
          abi.encodePacked(
            "\x19\x01",
            DOMAIN_SEPARATOR(),
            keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _loadERC20Slot().nonces[owner]++, deadline))
          )
        ),
        v,
        r,
        s
      );

      require(recoveredAddress != address(0) && recoveredAddress == owner, "INVALID_SIGNER");

      _loadERC20Slot().allowance[recoveredAddress][spender] = value;
    }

    emit Approval(owner, spender, value);
  }

  // solhint-disable-next-line func-name-mixedcase
  function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
    return computeDomainSeparator();
  }

  function computeDomainSeparator() internal view virtual returns (bytes32) {
    return
      keccak256(
        abi.encode(
          keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)"),
          keccak256("1"),
          block.chainid,
          address(this)
        )
      );
  }

  function _mint(address to, uint256 amount) internal virtual {
    ERC20Data storage s = _loadERC20Slot();
    s._totalSupply += amount;

    // Cannot overflow because the sum of all user
    // balances can't exceed the max uint256 value.
    unchecked {
      s.balanceOf[to] += amount;
    }
  }

  function _burn(address from, uint256 amount) internal virtual {
    ERC20Data storage s = _loadERC20Slot();
    s.balanceOf[from] -= amount;

    // Cannot underflow because a user's balance
    // will never be larger than the total supply.
    unchecked {
      s._totalSupply -= amount;
    }
  }
}
