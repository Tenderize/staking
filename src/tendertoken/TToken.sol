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

import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

import { IERC20 } from "core/interfaces/IERC20.sol";
import { TTokenStorage } from "core/tendertoken/TTokenStorage.sol";

/// @notice Non-standard ERC20 + EIP-2612 implementation.
/// @author Tenderize
/// @author Modified from Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @dev Do not mint shares without updating the total supply without being unaware of the consequences (see
/// `_mintShares` and `_burnShares`).

abstract contract TToken is TTokenStorage, IERC20 {
    using FixedPointMathLib for uint256;

    error ZeroAmount();
    error InvalidSignature();
    error PermitDeadlineExpired(uint256 expiryTimestamp, uint256 currentTimestamp);

    bytes32 private constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    uint8 private constant DECIMALS = 18;

    function decimals() public pure returns (uint8) {
        return DECIMALS;
    }

    function name() external view virtual returns (string memory);

    function symbol() external view virtual returns (string memory);

    function convertToAssets(uint256 shares) public view returns (uint256) {
        Storage storage $ = _loadStorage();

        uint256 _totalShares = $._totalShares; // Saves an extra SLOAD if slot is non-zero
        return _totalShares == 0 ? shares : shares.mulDivDown($._totalSupply, _totalShares);
    }

    function convertToShares(uint256 assets) public view returns (uint256) {
        Storage storage $ = _loadStorage();

        uint256 _totalShares = $._totalShares; // Saves an extra SLOAD if slot is non-zero
        return _totalShares == 0 ? assets : assets.mulDivDown(_totalShares, $._totalSupply);
    }

    function balanceOf(address account) public view virtual returns (uint256) {
        return convertToAssets(_loadStorage().shares[account]);
    }

    function totalSupply() public view virtual returns (uint256) {
        Storage storage $ = _loadStorage();
        return $._totalSupply;
    }

    function nonces(address owner) external view returns (uint256) {
        Storage storage $ = _loadStorage();
        return $.nonces[owner];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        Storage storage $ = _loadStorage();
        $.allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        Storage storage $ = _loadStorage();
        uint256 shares = convertToShares(amount);
        // underflows if insufficient balance
        $.shares[msg.sender] -= shares;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            $.shares[to] += shares;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        Storage storage $ = _loadStorage();
        return $.allowance[owner][spender];
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        Storage storage $ = _loadStorage();
        uint256 allowed = $.allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) {
            $.allowance[from][msg.sender] = allowed - amount;
        }

        uint256 shares = convertToShares(amount);

        $.shares[from] -= shares;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            $.shares[to] += shares;
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
    )
        public
        virtual
    {
        if (deadline < block.timestamp) revert PermitDeadlineExpired(deadline, block.timestamp);

        // Unchecked because the only math done is incrementing
        // the owner's nonce which cannot realistically overflow.

        unchecked {
            address recoveredAddress = ecrecover(
                keccak256(
                    abi.encodePacked(
                        "\x19\x01",
                        DOMAIN_SEPARATOR(),
                        keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _loadStorage().nonces[owner]++, deadline))
                    )
                ),
                v,
                r,
                s
            );

            if (recoveredAddress == address(0) || recoveredAddress != owner) revert InvalidSignature();

            _loadStorage().allowance[recoveredAddress][spender] = value;
        }

        emit Approval(owner, spender, value);
    }

    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() public view virtual returns (bytes32) {
        return keccak256(
            abi.encode(
                keccak256("EIP712Domain(string version,uint256 chainId,address verifyingContract)"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    function _setTotalSupply(uint256 supply) internal virtual {
        Storage storage $ = _loadStorage();
        $._totalSupply = supply;
    }

    function _mint(address to, uint256 assets) internal virtual {
        uint256 shares;

        if (assets == 0) revert ZeroAmount();
        if ((shares = convertToShares(assets)) == 0) return;

        Storage storage $ = _loadStorage();
        $._totalSupply += assets;
        $._totalShares += shares;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            $.shares[to] += shares;
        }
    }

    function _burn(address from, uint256 assets) internal virtual {
        uint256 shares;

        if (assets == 0) revert ZeroAmount();
        if ((shares = convertToShares(assets)) == 0) return;

        Storage storage $ = _loadStorage();
        $._totalSupply -= assets;
        $.shares[from] -= shares;

        // Cannot underflow because a user's balance
        // will never be larger than the total supply.
        unchecked {
            $._totalShares -= shares;
        }
    }
}
