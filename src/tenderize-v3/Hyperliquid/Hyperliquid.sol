pragma solidity ^0.8.25;

address constant DELEGATIONS_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000804;
address constant DELEGATOR_SUMMARY_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000805;
address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

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

interface Hyperliquid {
    function delegatorSummary(address user) external view returns (DelegatorSummary memory);
    function delegations(address user) external view returns (Delegation[] memory);
    function sendTokenDelegate(address validator, uint64 _wei, bool isUndelegate) external;
}
