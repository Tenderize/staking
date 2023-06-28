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

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { Adapter, AdapterDelegateCall } from "core/adapters/Adapter.sol";
import { Registry } from "core/registry/Registry.sol";
import { TenderizerImmutableArgs, TenderizerEvents } from "core/tenderizer/TenderizerBase.sol";
import { TToken } from "core/tendertoken/TToken.sol";

/**
 * @title Tenderizer
 * @author Tenderize Labs Ltd
 * @notice Liquid staking vault for native liquid staking
 * @dev Uses full type safety and unstructured storage
 */

contract Tenderizer is TenderizerImmutableArgs, TenderizerEvents, TToken {
    error InsufficientAssets();

    using AdapterDelegateCall for Adapter;
    using FixedPointMathLib for uint256;
    using SafeTransferLib for ERC20;

    uint256 private constant MAX_FEE = 0.005e6; // 0.5%
    uint256 private constant FEE_BASE = 1e6;

    // @inheritdoc TToken
    function name() external view override returns (string memory) {
        return string(abi.encodePacked("tender", ERC20(asset()).symbol(), " ", validator()));
    }

    // @inheritdoc TToken
    function symbol() external view override returns (string memory) {
        return string(abi.encodePacked("t", ERC20(asset()).symbol(), "_", validator()));
    }

    // @inheritdoc TToken
    function transfer(address to, uint256 amount) public override returns (bool) {
        _rebase();
        return TToken.transfer(to, amount);
    }

    // @inheritdoc TToken
    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _rebase();
        return TToken.transferFrom(from, to, amount);
    }

    /**
     * @notice Deposit assets to mint tTokens
     * @param receiver address to mint tTokens to
     * @param assets amount of assets to deposit
     */
    function deposit(address receiver, uint256 assets) external returns (uint256) {
        _rebase();

        // transfer tokens before minting (or ERC777's could re-enter)
        ERC20(asset()).safeTransferFrom(msg.sender, address(this), assets);

        // preview deposit to get actual assets to mint for
        // deducts any possible third-party protocol taxes or fees
        uint256 actualAssets = _previewDeposit(assets);

        // stake assets
        _stake(validator(), assets);

        // mint tokens to receiver
        uint256 shares;
        if ((shares = _mint(receiver, actualAssets)) == 0) revert InsufficientAssets();

        uint256 tTokenOut = convertToAssets(shares);
        emit Deposit(msg.sender, receiver, assets, tTokenOut);

        return tTokenOut;
    }

    /**
     * @notice Unlock tTokens to withdraw assets at maturity
     * @param assets amount of assets to unlock
     * @return unlockID of the unlock
     */
    function unlock(uint256 assets) external returns (uint256 unlockID) {
        _rebase();

        // burn tTokens before creating an `unlock`
        _burn(msg.sender, assets);

        // unlock assets and get unlockID
        unlockID = _unstake(validator(), assets);

        // create unlock of unlockID
        _unlocks().createUnlock(msg.sender, unlockID);

        // emit Unlock event
        emit Unlock(msg.sender, assets, unlockID);
    }

    /**
     * @notice Redeem an unlock to withdraw assets after maturity
     * @param receiver address to withdraw assets to
     * @param unlockID ID of the unlock to redeem
     * @return amount of assets withdrawn
     */
    function withdraw(address receiver, uint256 unlockID) external returns (uint256 amount) {
        // Redeem unlock if mature
        _unlocks().useUnlock(msg.sender, unlockID);

        // withdraw assets to send to `receiver`
        amount = _withdraw(validator(), unlockID);

        // transfer assets to `receiver`
        ERC20(asset()).safeTransfer(receiver, amount);

        // emit Withdraw event
        emit Withdraw(receiver, amount, unlockID);
    }

    /**
     * @notice Rebase tToken supply
     * @dev Rebase can be called by anyone, is also forced to be called before any action or transfer
     */
    function rebase() external {
        _rebase();
    }

    function _rebase() internal {
        uint256 currentStake = totalSupply();
        uint256 newStake = _rebase(validator(), currentStake);

        if (newStake > currentStake) {
            unchecked {
                uint256 rewards = newStake - currentStake;
                uint256 fees = _calculateFees(rewards);
                _setTotalSupply(newStake - fees);
                // mint fees
                if (fees > 0) {
                    _mint(Registry(_registry()).treasury(), fees);
                }
            }
        } else {
            _setTotalSupply(newStake);
        }

        // emit rebase event
        emit Rebase(currentStake, newStake);
    }

    function _calculateFees(uint256 rewards) internal view returns (uint256 fees) {
        uint256 fee = Registry(_registry()).fee(asset());
        fee = fee > MAX_FEE ? MAX_FEE : fee;
        fees = rewards * fee / FEE_BASE;
    }

    function _adapter() internal view returns (Adapter) {
        return Adapter(Registry(_registry()).adapter(asset()));
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        return abi.decode(_staticcall(address(this), abi.encodeCall(this._previewDeposit, (assets))), (uint256));
    }

    function previewWithdraw(uint256 unlockID) external view returns (uint256) {
        return abi.decode(_staticcall(address(this), abi.encodeCall(this._previewWithdraw, (unlockID))), (uint256));
    }

    function unlockMaturity(uint256 unlockID) external view returns (uint256) {
        return abi.decode(_staticcall(address(this), abi.encodeCall(this._unlockMaturity, (unlockID))), (uint256));
    }

    // ===============================================================================================================
    // NOTE: These functions are marked `public` but considered `internal` (hence the `_` prefix).
    // This is because the compiler doesn't know whether there is a state change because of `delegatecall``
    // So for the external API (e.g. used by Unlocks.sol) we wrap these functions in `external` functions
    // using a `staticcall` to `this`.
    // This is a hacky workaround while better solidity features are being developed.
    function _previewDeposit(uint256 assets) public returns (uint256) {
        return abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().previewDeposit, (assets))), (uint256));
    }

    function _previewWithdraw(uint256 unlockID) public returns (uint256) {
        return abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().previewWithdraw, (unlockID))), (uint256));
    }

    function _unlockMaturity(uint256 unlockID) public returns (uint256) {
        return abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().unlockMaturity, (unlockID))), (uint256));
    }
    // ===============================================================================================================

    function _rebase(address validator, uint256 currentStake) internal returns (uint256 newStake) {
        newStake = abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().rebase, (validator, currentStake))), (uint256));
    }

    function _stake(address validator, uint256 amount) internal {
        _adapter()._delegatecall(abi.encodeCall(_adapter().stake, (validator, amount)));
    }

    function _unstake(address validator, uint256 amount) internal returns (uint256 unlockID) {
        unlockID = abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().unstake, (validator, amount))), (uint256));
    }

    function _withdraw(address validator, uint256 unlockID) internal returns (uint256 withdrawAmount) {
        withdrawAmount = abi.decode(_adapter()._delegatecall(abi.encodeCall(_adapter().withdraw, (validator, unlockID))), (uint256));
    }
}

error StaticCallFailed(address to, bytes data, string message);

function _staticcall(address target, bytes memory data) view returns (bytes memory) {
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, bytes memory returnData) = address(target).staticcall(data);

    if (!success) {
        if (returnData.length < 68) revert StaticCallFailed(address(target), data, "");
        assembly {
            returnData := add(returnData, 0x04)
        }
        revert StaticCallFailed(address(target), data, abi.decode(returnData, (string)));
    }

    return returnData;
}
