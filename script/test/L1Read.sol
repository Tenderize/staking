// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract L1Read {
    struct Position {
        int64 szi;
        uint32 leverage;
        uint64 entryNtl;
    }

    struct SpotBalance {
        uint64 total;
        uint64 hold;
        uint64 entryNtl;
    }

    struct UserVaultEquity {
        uint64 equity;
    }

    struct Withdrawable {
        uint64 withdrawable;
    }

    struct Delegation {
        address validator;
        uint64 amount;
        uint64 lockedUntilTimestamp;
    }

    struct DelegatorSummary {
        uint64 delegated;
        uint64 undelegated;
        uint64 totalPendingWithdrawal;
        uint64 nPendingWithdrawals;
    }

    address constant POSITION_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000800;
    address constant SPOT_BALANCE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000801;
    address constant VAULT_EQUITY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000802;
    address constant WITHDRAWABLE_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000803;
    address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
    address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;
    address constant MARK_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000806;
    address constant ORACLE_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000807;
    address constant SPOT_PX_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000808;
    address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

    function position(address user, uint16 perp) external view returns (Position memory) {
        bool success;
        bytes memory result;
        (success, result) = POSITION_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, perp));
        require(success, "Position precompile call failed");
        return abi.decode(result, (Position));
    }

    function spotBalance(address user, uint64 token) external view returns (SpotBalance memory) {
        bool success;
        bytes memory result;
        (success, result) = SPOT_BALANCE_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, token));
        require(success, "SpotBalance precompile call failed");
        return abi.decode(result, (SpotBalance));
    }

    function userVaultEquity(address user, address vault) external view returns (UserVaultEquity memory) {
        bool success;
        bytes memory result;
        (success, result) = VAULT_EQUITY_PRECOMPILE_ADDRESS.staticcall(abi.encode(user, vault));
        require(success, "VaultEquity precompile call failed");
        return abi.decode(result, (UserVaultEquity));
    }

    function withdrawable(address user) external view returns (Withdrawable memory) {
        bool success;
        bytes memory result;
        (success, result) = WITHDRAWABLE_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
        require(success, "Withdrawable precompile call failed");
        return abi.decode(result, (Withdrawable));
    }

    function delegations(address user) external view returns (Delegation[] memory) {
        bool success;
        bytes memory result;
        (success, result) = DELEGATIONS_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
        require(success, "Delegations precompile call failed");
        return abi.decode(result, (Delegation[]));
    }

    function delegatorSummary(address user) external view returns (DelegatorSummary memory) {
        bool success;
        bytes memory result;
        (success, result) = DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS.staticcall(abi.encode(user));
        require(success, "DelegatorySummary precompile call failed");
        return abi.decode(result, (DelegatorSummary));
    }

    function markPx(uint16 index) external view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = MARK_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "MarkPx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function oraclePx(uint16 index) external view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = ORACLE_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "OraclePx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function spotPx(uint32 index) external view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = SPOT_PX_PRECOMPILE_ADDRESS.staticcall(abi.encode(index));
        require(success, "SpotPx precompile call failed");
        return abi.decode(result, (uint64));
    }

    function l1BlockNumber() public view returns (uint64) {
        bool success;
        bytes memory result;
        (success, result) = L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS.staticcall(abi.encode());
        require(success, "L1BlockNumber precompile call failed");
        return abi.decode(result, (uint64));
    }
}
