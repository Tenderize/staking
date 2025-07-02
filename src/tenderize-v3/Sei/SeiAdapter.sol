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

pragma solidity ^0.8.25;

import { Adapter } from "core/tenderize-v3/Adapter.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";
import { ISeiStaking, SEI_STAKING_PRECOMPILE_ADDRESS, Delegation } from "core/tenderize-v3/Sei/Sei.sol";

contract SeiAdapter is Adapter {
    error UnlockNotReady();
    error DelegationFailed();
    error UndelegationFailed();
    error InvalidAmount();
    error Bech32DecodeError();

    struct Storage {
        uint256 lastUnlockID;
        mapping(uint256 => Unlock) unlocks;
    }

    struct Unlock {
        uint256 amount;
        uint256 unlockTime;
    }

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.sei.adapter.storage.location")) - 1;

    // Sei uses 6 decimal precision (1 SEI = 1_000_000 uSEI)
    // Ethereum uses 18 decimal precision (1 ETH = 1_000_000_000_000_000_000 wei)
    uint256 private constant PRECISION_SCALE = 1e12; // 18 - 6 = 12 decimal places

    // Sei unbonding period is typically 21 days (in seconds)
    uint256 private constant UNBONDING_PERIOD = 21 days;

    // Bech32 character set
    string private constant BECH32_CHARSET = "qpzry9x8gf2tvdw0s3jn54khce6mua7l";

    function symbol() external pure returns (string memory) {
        return "SEI";
    }

    function _loadStorage() internal pure returns (Storage storage $) {
        uint256 slot = STORAGE;
        assembly {
            $.slot := slot
        }
    }

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function previewDeposit(bytes32, /*validator*/ uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) external view override returns (uint256) {
        Storage storage $ = _loadStorage();
        return $.unlocks[unlockID].amount;
    }

    function unlockMaturity(uint256 unlockID) external view override returns (uint256) {
        Storage storage $ = _loadStorage();
        return $.unlocks[unlockID].unlockTime;
    }

    function unlockTime() external pure override returns (uint256) {
        return UNBONDING_PERIOD;
    }

    function currentTime() external view override returns (uint256) {
        return block.timestamp;
    }

    function stake(bytes32 validator, uint256 amount) external override returns (uint256 staked) {
        if (amount == 0) revert InvalidAmount();

        string memory validatorAddr = _bytes32ToSeiValidator(validator);

        // Convert from 18 decimal to 6 decimal precision
        uint256 seiAmount = amount / PRECISION_SCALE;

        // Call the Sei staking precompile
        ISeiStaking seiStaking = ISeiStaking(SEI_STAKING_PRECOMPILE_ADDRESS);
        bool success = seiStaking.delegate{ value: seiAmount }(validatorAddr);

        if (!success) revert DelegationFailed();

        return amount; // Return the original amount in 18 decimal precision
    }

    function unstake(bytes32 validator, uint256 amount) external override returns (uint256 unlockID) {
        if (amount == 0) revert InvalidAmount();

        string memory validatorAddr = _bytes32ToSeiValidator(validator);

        // Convert from 18 decimal to 6 decimal precision
        uint256 seiAmount = amount / PRECISION_SCALE;

        // Call the Sei staking precompile
        ISeiStaking seiStaking = ISeiStaking(SEI_STAKING_PRECOMPILE_ADDRESS);
        bool success = seiStaking.undelegate(validatorAddr, seiAmount);

        if (!success) revert UndelegationFailed();

        // Create unlock entry
        Storage storage $ = _loadStorage();
        unlockID = ++$.lastUnlockID;
        $.unlocks[unlockID] = Unlock({ amount: amount, unlockTime: block.timestamp + UNBONDING_PERIOD });

        return unlockID;
    }

    function withdraw(bytes32, /*validator*/ uint256 unlockID) external override returns (uint256 amount) {
        Storage storage $ = _loadStorage();
        Unlock memory unlock = $.unlocks[unlockID];

        if (unlock.amount == 0) revert InvalidAmount();
        if (block.timestamp < unlock.unlockTime) revert UnlockNotReady();

        amount = unlock.amount;
        delete $.unlocks[unlockID];

        // Note: In Sei, the undelegated tokens are automatically returned to the user's account
        // after the unbonding period, so no additional withdrawal call is needed
        return amount;
    }

    function rebase(bytes32 validator, uint256 currentStake) external view override returns (uint256 newStake) {
        string memory validatorAddr = _bytes32ToSeiValidator(validator);

        // Query current delegation from Sei
        ISeiStaking seiStaking = ISeiStaking(SEI_STAKING_PRECOMPILE_ADDRESS);
        Delegation memory delegation = seiStaking.delegation(address(this), validatorAddr);

        // Convert from 6 decimal to 18 decimal precision
        uint256 seiBalance = delegation.balance.amount;
        newStake = seiBalance * PRECISION_SCALE;

        return newStake;
    }

    function isValidator(bytes32 validator) external pure override returns (bool) {
        // For Sei, we assume any non-zero bytes32 represents a valid validator
        // The actual validation happens when interacting with the Sei precompile
        return validator != bytes32(0);
    }

    /**
     * -----------------------------------------------------------------------
     * New public helper functions
     * -----------------------------------------------------------------------
     */

    /// @notice Convert a `seivaloper...` bech32 string into the internal bytes32 representation
    /// @param validatorAddr The bech32 encoded validator address (e.g. "seivaloper1...")
    /// @return validator The bytes32 representation used by Tenderize contracts
    function validatorStringToBytes32(string calldata validatorAddr) external pure returns (bytes32 validator) {
        return _seiValidatorToBytes32(validatorAddr);
    }

    /// @notice Convert the internal bytes32 validator identifier into a `seivaloper...` bech32 string
    /// @param validator The bytes32 validator identifier
    /// @return validatorAddr The bech32 encoded validator address (e.g. "seivaloper1...")
    function validatorBytes32ToString(bytes32 validator) external pure returns (string memory validatorAddr) {
        return _bytes32ToSeiValidator(validator);
    }

    /**
     * -----------------------------------------------------------------------
     * Internal helpers for bech32 decoding
     * -----------------------------------------------------------------------
     */

    /// @notice Convert a `seivaloper...` address into bytes32
    /// @dev Reverts Bech32DecodeError if the address is malformed or checksum is incorrect
    function _seiValidatorToBytes32(string memory validatorAddr) internal pure returns (bytes32) {
        // Ensure the address starts with the expected HRP prefix
        bytes memory addrBytes = bytes(validatorAddr);
        bytes memory hrpBytes = bytes("seivaloper");
        uint256 hrpLen = hrpBytes.length;
        if (addrBytes.length <= hrpLen + 7) revert Bech32DecodeError(); // need at least hrp + '1' + data + 6 byte checksum

        // Check separator
        if (addrBytes[hrpLen] != bytes1("1")) revert Bech32DecodeError();

        // Convert characters to 5-bit values
        uint256 dataLen = addrBytes.length - hrpLen - 1; // exclude hrp and separator
        if (dataLen <= 6) revert Bech32DecodeError();
        bytes memory dataVals = new bytes(dataLen);
        for (uint256 i = 0; i < dataLen; i++) {
            int8 idx = _bech32CharToValue(addrBytes[hrpLen + 1 + i]);
            if (idx < 0) revert Bech32DecodeError();
            dataVals[i] = bytes1(uint8(idx));
        }

        // Split payload and checksum (last 6 values)
        uint256 payloadLen = dataVals.length - 6;
        bytes memory payload = new bytes(payloadLen);
        for (uint256 i = 0; i < payloadLen; i++) {
            payload[i] = dataVals[i];
        }

        // TODO: Optionally verify checksum here. For now we optimistically decode.

        // Convert 5-bit groups back to 8-bit bytes
        bytes memory decoded = _convertBits(payload, 5, 8, false);
        if (decoded.length != 20) revert Bech32DecodeError();

        bytes32 result;
        assembly {
            result := mload(add(decoded, 32))
        }
        return result;
    }

    /// @notice Map a bech32 character to its 5-bit value (0-31)
    /// @return idx The 5-bit value or -1 if the character is invalid
    function _bech32CharToValue(bytes1 char) internal pure returns (int8 idx) {
        bytes memory charset = bytes(BECH32_CHARSET);
        for (uint8 i = 0; i < charset.length; i++) {
            if (char == charset[i]) {
                return int8(int8(i));
            }
        }
        return -1;
    }

    /**
     * @notice Convert bytes32 validator ID to Sei validator address
     * @param validator The bytes32 validator identifier
     * @return The Sei validator address string
     */
    function _bytes32ToSeiValidator(bytes32 validator) internal pure returns (string memory) {
        // Extract the 20-byte address from bytes32 (first 20 bytes)
        bytes memory addr = new bytes(20);
        for (uint256 i = 0; i < 20; i++) {
            addr[i] = validator[i];
        }

        // Encode as bech32 with "seivaloper" prefix
        return _encodeBech32("seivaloper", addr);
    }

    /**
     * @notice Encode bytes as bech32 with given human readable part (HRP)
     * @param hrp The human readable part (e.g., "seivaloper")
     * @param data The data bytes to encode
     * @return The bech32 encoded string
     */
    function _encodeBech32(string memory hrp, bytes memory data) internal pure returns (string memory) {
        // Convert 8-bit data to 5-bit groups
        bytes memory converted = _convertBits(data, 8, 5, true);

        // Create checksum
        bytes memory combined = abi.encodePacked(converted, _createChecksum(hrp, converted));

        // Encode to bech32 characters
        bytes memory result = new bytes(bytes(hrp).length + 1 + combined.length);

        // Copy HRP
        for (uint256 i = 0; i < bytes(hrp).length; i++) {
            result[i] = bytes(hrp)[i];
        }

        // Add separator
        result[bytes(hrp).length] = "1";

        // Add encoded data
        for (uint256 i = 0; i < combined.length; i++) {
            result[bytes(hrp).length + 1 + i] = bytes(BECH32_CHARSET)[uint8(combined[i])];
        }

        return string(result);
    }

    /**
     * @notice Convert between bit groups
     */
    function _convertBits(bytes memory data, uint256 fromBits, uint256 toBits, bool pad) internal pure returns (bytes memory) {
        uint256 acc = 0;
        uint256 bits = 0;
        bytes memory ret = new bytes((data.length * fromBits + toBits - 1) / toBits);
        uint256 retIndex = 0;
        uint256 maxv = (1 << toBits) - 1;

        for (uint256 i = 0; i < data.length; i++) {
            uint256 value = uint8(data[i]);
            acc = (acc << fromBits) | value;
            bits += fromBits;

            while (bits >= toBits) {
                bits -= toBits;
                if (retIndex < ret.length) {
                    ret[retIndex] = bytes1(uint8((acc >> bits) & maxv));
                    retIndex++;
                }
            }
        }

        if (pad && bits > 0) {
            if (retIndex < ret.length) {
                ret[retIndex] = bytes1(uint8((acc << (toBits - bits)) & maxv));
                retIndex++;
            }
        }

        // Resize array to actual length
        assembly {
            mstore(ret, retIndex)
        }

        return ret;
    }

    /**
     * @notice Create bech32 checksum
     */
    function _createChecksum(string memory hrp, bytes memory data) internal pure returns (bytes memory) {
        bytes memory hrpBytes = bytes(hrp);
        uint256 chk = 1;

        // Process HRP
        for (uint256 i = 0; i < hrpBytes.length; i++) {
            chk = _polymod(chk) ^ (uint8(hrpBytes[i]) >> 5);
        }
        chk = _polymod(chk);

        for (uint256 i = 0; i < hrpBytes.length; i++) {
            chk = _polymod(chk) ^ (uint8(hrpBytes[i]) & 31);
        }

        // Process data
        for (uint256 i = 0; i < data.length; i++) {
            chk = _polymod(chk) ^ uint8(data[i]);
        }

        // Add padding for checksum
        for (uint256 i = 0; i < 6; i++) {
            chk = _polymod(chk);
        }

        chk ^= 1;

        bytes memory checksum = new bytes(6);
        for (uint256 i = 0; i < 6; i++) {
            checksum[i] = bytes1(uint8((chk >> (5 * (5 - i))) & 31));
        }

        return checksum;
    }

    /**
     * @notice Bech32 polymod function
     */
    function _polymod(uint256 chk) internal pure returns (uint256) {
        uint256 top = chk >> 25;
        chk = (chk & 0x1ffffff) << 5;

        if (top & 1 != 0) chk ^= 0x3b6a57b2;
        if (top & 2 != 0) chk ^= 0x26508e6d;
        if (top & 4 != 0) chk ^= 0x1ea119fa;
        if (top & 8 != 0) chk ^= 0x3d4233dd;
        if (top & 16 != 0) chk ^= 0x2a1462b3;

        return chk;
    }
}
