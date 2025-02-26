pragma solidity >=0.8.25;

import { Script, console2 } from "forge-std/Script.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { HypeAdapter } from "core/tenderize-v3/Hyperliquid/HypeAdapter.sol";
import { L1Read } from "./L1Read.sol";

address constant L1_BLOCK_NUMBER_PRECOMPILE_ADDRESS = 0x0000000000000000000000000000000000000809;

address constant SEI_PRECOMPILE = 0x0000000000000000000000000000000000001005;

interface Sei {
    // Queries
    function delegation(address delegator, string memory valAddress) external view returns (Delegation memory delegation);

    struct Delegation {
        Balance balance;
        DelegationDetails delegation;
    }

    struct Balance {
        uint256 amount;
        string denom;
    }

    struct DelegationDetails {
        string delegator_address;
        uint256 shares;
        uint256 decimals;
        string validator_address;
    }
}

contract SeiAdapterTest is Script, L1Read {
    function run() public {
        string memory val = "seivaloper1y82m5y3wevjneamzg0pmx87dzanyxzht0kepvn";
        uint256 blockNumber = Sei(SEI_PRECOMPILE).delegation(address(this), val).delegation.shares;
        console2.log(blockNumber);
    }
}
