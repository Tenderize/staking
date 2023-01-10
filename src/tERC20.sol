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

interface IERC20Metadata {
  /**
   * @dev Returns the name of the token.
   */
  function name() external view returns (string memory);

  /**
   * @dev Returns the symbol of the token.
   */
  function symbol() external view returns (string memory);

  /**
   * @dev Returns the decimals places of the token.
   */
  function decimals() external view returns (uint8);
}

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 is IERC20Metadata {
  /**
   * @dev Emitted when `value` tokens are moved from one account (`from`) to
   * another (`to`).
   *
   * Note that `value` may be zero.
   */
  event Transfer(address indexed from, address indexed to, uint256 value);

  /**
   * @dev Emitted when the allowance of a `spender` for an `owner` is set by
   * a call to {approve}. `value` is the new allowance.
   */
  event Approval(address indexed owner, address indexed spender, uint256 value);

  /**
   * @dev Returns the amount of tokens in existence.
   */
  function totalSupply() external view returns (uint256);

  /**
   * @dev Returns the amount of tokens owned by `account`.
   */
  function balanceOf(address account) external view returns (uint256);

  /**
   * @dev Moves `amount` tokens from the caller's account to `to`.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transfer(address to, uint256 amount) external returns (bool);

  /**
   * @dev Returns the remaining number of tokens that `spender` will be
   * allowed to spend on behalf of `owner` through {transferFrom}. This is
   * zero by default.
   *
   * This value changes when {approve} or {transferFrom} are called.
   */
  function allowance(address owner, address spender) external view returns (uint256);

  /**
   * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * IMPORTANT: Beware that changing an allowance with this method brings the risk
   * that someone may use both the old and the new allowance by unfortunate
   * transaction ordering. One possible solution to mitigate this race
   * condition is to first reduce the spender's allowance to 0 and set the
   * desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   *
   * Emits an {Approval} event.
   */
  function approve(address spender, uint256 amount) external returns (bool);

  /**
   * @dev Moves `amount` tokens from `from` to `to` using the
   * allowance mechanism. `amount` is then deducted from the caller's
   * allowance.
   *
   * Returns a boolean value indicating whether the operation succeeded.
   *
   * Emits a {Transfer} event.
   */
  function transferFrom(
    address from,
    address to,
    uint256 amount
  ) external returns (bool);
}

/// @notice Non-standard ERC20 + EIP-2612 implementation.
/// @author Tenderize
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.

abstract contract tERC20 is IERC20 {
  uint256 constant ERC20_SLOT = uint256(keccak256("xyz.tenderize.ERC20.storage.location")) - 1;
  bytes32 private constant PERMIT_TYPEHASH =
    keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

  struct ERC20Data {
    uint256 _totalSupply;
    mapping(address => uint256) balanceOf;
    mapping(address => mapping(address => uint256)) allowance;
    mapping(address => uint256) nonces;
  }

  function _loadERC20Slot() internal pure returns (ERC20Data storage s) {
    uint256 slot = ERC20_SLOT;

    assembly {
      s.slot := slot
    }
  }

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

    emit Transfer(address(0), to, amount);
  }

  function _burn(address from, uint256 amount) internal virtual {
    ERC20Data storage s = _loadERC20Slot();
    s.balanceOf[from] -= amount;

    // Cannot underflow because a user's balance
    // will never be larger than the total supply.
    unchecked {
      s._totalSupply -= amount;
    }

    emit Transfer(from, address(0), amount);
  }
}
