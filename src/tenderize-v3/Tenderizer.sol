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

import { Unlocks } from "core/unlocks/Unlocks.sol";
import { Registry } from "core/registry/Registry.sol";
import { Adapter, AdapterDelegateCall } from "core/tenderize-v3/Adapter.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { Multicall } from "core/utils/Multicall.sol";
import { SelfPermit } from "core/utils/SelfPermit.sol";
import { TenderizerEvents } from "core/tenderizer/TenderizerBase.sol";
import { addressToString } from "core/utils/Utils.sol";
import { _staticcall } from "core/utils/StaticCall.sol";

import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";

contract Tenderizer is Initializable, TenderizerEvents, TToken, Multicall, SelfPermit {
    using AdapterDelegateCall for Adapter;

    error InsufficientAssets();

    uint256 private constant MAX_FEE = 0.005e6; // 0.5%
    uint256 private constant FEE_BASE = 1e6;

    address public immutable asset;
    address private immutable registry;
    address private immutable unlocks;

    bytes32 public validator;

    constructor(address _asset, address _registry, address _unlocks) {
        asset = _asset;
        registry = _registry;
        unlocks = _unlocks;
        _disableInitializers();
    }

    function initialize(bytes32 _validator) public initializer {
        validator = _validator;
    }

    // @inheritdoc TToken
    function name() external view override returns (string memory) {
        return string.concat("tender ", adapter().symbol());
    }

    // @inheritdoc TToken
    function symbol() external view override returns (string memory) {
        return string.concat("t", adapter().symbol());
    }

    function adapter() public view returns (Adapter) {
        return Adapter(_registry().adapter(asset));
    }

    function _registry() internal view returns (Registry) {
        return Registry(registry);
    }

    function _unlocks() internal view returns (Unlocks) {
        return Unlocks(unlocks);
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
     */
    function deposit(address receiver) external payable returns (uint256) {
        _rebase();

        // transfer tokens before minting (or ERC777's could re-enter)
        // ERC20(asset()).safeTransferFrom(msg.sender, address(this), msg.value);

        // stake assets
        uint256 staked = _stake(validator, msg.value);

        // mint tokens to receiver
        uint256 shares;
        if ((shares = _mint(receiver, staked)) == 0) revert InsufficientAssets();

        uint256 tTokenOut = convertToAssets(shares);
        emit Deposit(msg.sender, receiver, msg.value, tTokenOut);

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
        unlockID = _unstake(validator, assets);

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
    function withdraw(address payable receiver, uint256 unlockID) external returns (uint256 amount) {
        // Redeem unlock if mature
        _unlocks().useUnlock(msg.sender, unlockID);

        // withdraw assets to send to `receiver`
        amount = _withdraw(validator, unlockID);

        // transfer assets to `receiver`
        receiver.transfer(amount);

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
        uint256 newStake = _rebase(validator, currentStake);

        if (newStake > currentStake) {
            unchecked {
                uint256 rewards = newStake - currentStake;
                uint256 fees = _calculateFees(rewards);
                _setTotalSupply(newStake - fees);
                // mint fees
                if (fees > 0) {
                    _mint(_registry().treasury(), fees);
                }
            }
        } else {
            _setTotalSupply(newStake);
        }

        // emit rebase event
        emit Rebase(currentStake, newStake);
    }

    function _calculateFees(uint256 rewards) internal view returns (uint256 fees) {
        uint256 fee = _registry().fee(asset);
        fee = fee > MAX_FEE ? MAX_FEE : fee;
        fees = rewards * fee / FEE_BASE;
    }

    function previewDeposit(uint256 assets) external view returns (uint256) {
        uint256 out = abi.decode(_staticcall(address(this), abi.encodeCall(this._previewDeposit, (assets))), (uint256));
        Storage storage $ = _loadStorage();
        uint256 _totalShares = $._totalShares; // Saves an extra SLOAD if slot is non-zero
        uint256 shares = convertToShares(out);
        return _totalShares == 0 ? out : shares * $._totalSupply / _totalShares;
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
        return abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().previewDeposit, (validator, assets))), (uint256));
    }

    function _previewWithdraw(uint256 unlockID) public returns (uint256) {
        return abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().previewWithdraw, (unlockID))), (uint256));
    }

    function _unlockMaturity(uint256 unlockID) public returns (uint256) {
        return abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().unlockMaturity, (unlockID))), (uint256));
    }
    // ===============================================================================================================

    function _rebase(bytes32 validator, uint256 currentStake) internal returns (uint256 newStake) {
        newStake = abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().rebase, (validator, currentStake))), (uint256));
    }

    function _stake(bytes32 validator, uint256 amount) internal returns (uint256 staked) {
        staked = abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().stake, (validator, amount))), (uint256));
    }

    function _unstake(bytes32 validator, uint256 amount) internal returns (uint256 unlockID) {
        unlockID = abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().unstake, (validator, amount))), (uint256));
    }

    function _withdraw(bytes32 validator, uint256 unlockID) internal returns (uint256 withdrawAmount) {
        withdrawAmount = abi.decode(adapter()._delegatecall(abi.encodeCall(adapter().withdraw, (validator, unlockID))), (uint256));
    }
}
