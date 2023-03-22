// SPDX-License-Identifier: MIT
//
//  _____              _           _
// |_   _|            | |         (_)
//   | | ___ _ __   __| | ___ _ __ _ _______
//   | |/ _ \ '_ \ / _` |/ _ \ '__| |_  / _ \
//   | |  __/ | | | (_| |  __/ |  | |/ /  __/
//   \_/\___|_| |_|\__,_|\___|_|  |_/___\___|
//
// Copyright (c) Tenderize Labs Ltdpragma solidity >=0.8.17;

import { IERC20 } from "core/interfaces/IERC20.sol";
import { Clone } from "clones/Clone.sol";

/// @notice Modern and gas efficient ERC20 + EIP-2612 implementation.
/// @author Solmate (https://github.com/Rari-Capital/solmate/blob/main/src/tokens/ERC20.sol)
/// @author Modified from Uniswap (https://github.com/Uniswap/uniswap-v2-core/blob/master/contracts/UniswapV2ERC20.sol)
/// @dev Do not manually set balances without updating totalSupply, as the sum of all user balances must not exceed it.

abstract contract ERC20Cloned is IERC20 {
    uint256 private constant ERC20_SLOT = uint256(keccak256("xyz.tenderize.ERC20.storage.location")) - 1;
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

    function balanceOf(address account) external view returns (uint256) {
        return _loadERC20Slot().balanceOf[account];
    }

    function approve(address spender, uint256 amount) public virtual returns (bool) {
        ERC20Data storage s = _loadERC20Slot();
        s.allowance[msg.sender][spender] = amount;

        emit Approval(msg.sender, spender, amount);

        return true;
    }

    function transfer(address to, uint256 amount) public virtual returns (bool) {
        ERC20Data storage s = _loadERC20Slot();
        s.balanceOf[msg.sender] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            s.balanceOf[to] += amount;
        }

        emit Transfer(msg.sender, to, amount);

        return true;
    }

    function allowance(address owner, address spender) external view returns (uint256) {
        ERC20Data storage s = _loadERC20Slot();
        return s.allowance[owner][spender];
    }

    function totalSupply() public view virtual returns (uint256) {
        ERC20Data storage s = _loadERC20Slot();
        return s._totalSupply;
    }

    function transferFrom(address from, address to, uint256 amount) public virtual returns (bool) {
        ERC20Data storage s = _loadERC20Slot();
        uint256 allowed = s.allowance[from][msg.sender]; // Saves gas for limited approvals.

        if (allowed != type(uint256).max) {
            s.allowance[from][msg.sender] = allowed - amount;
        }

        s.balanceOf[from] -= amount;

        // Cannot overflow because the sum of all user
        // balances can't exceed the max uint256 value.
        unchecked {
            s.balanceOf[to] += amount;
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
        return keccak256(
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

contract LPToken is ERC20Cloned, Clone {
    error OnlyMetaPool(address caller, address metaPool);

    uint8 private constant DECIMALS = 18;

    modifier onlyMetaPool() {
        _onlyMetaPool();
        _;
    }

    function _onlyMetaPool() internal view {
        if (msg.sender != metaPool()) {
            revert OnlyMetaPool(msg.sender, metaPool());
        }
    }

    function underlying() public pure returns (address) {
        return _getArgAddress(0); // start: 0 end: 19
    }

    function metaPool() public pure returns (address) {
        return _getArgAddress(20); // start: 20 end: 39
    }

    function decimals() external pure returns (uint8) {
        return DECIMALS;
    }

    function name() external pure returns (string memory) {
        return "TenderSwap LP Token";
    }

    function symbol() external view returns (string memory) {
        return string(abi.encodePacked("SWAP ", IERC20(underlying()).symbol()));
    }

    function mint(address to, uint256 amount) external onlyMetaPool {
        _mint(to, amount);
    }

    function burn(address from, uint256 amount) external onlyMetaPool {
        _burn(from, amount);
    }
}
