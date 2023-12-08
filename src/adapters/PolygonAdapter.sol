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

pragma solidity >=0.8.19;

import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Adapter } from "core/adapters/Adapter.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";
import { ITenderizer } from "core/tenderizer/ITenderizer.sol";
import { IMaticStakeManager, IValidatorShares, DelegatorUnbond } from "core/adapters/interfaces/IPolygon.sol";

// Matic exchange rate precision
uint256 constant EXCHANGE_RATE_PRECISION = 100; // For Validator ID < 8
uint256 constant EXCHANGE_RATE_PRECISION_HIGH = 10 ** 29; // For Validator ID >= 8
uint256 constant WITHDRAW_DELAY = 80; // 80 epochs, epoch length can vary on average between 200-300 Ethereum L1 blocks

// Polygon validators with a `validatorId` less than 8 are foundation validators
// These are special case validators that don't have slashing enabled and still operate
// On the old precision for the ValidatorShares contract.
function getExchangePrecision(uint256 validatorId) pure returns (uint256) {
    if (validatorId < 8) {
        return EXCHANGE_RATE_PRECISION;
    } else {
        return EXCHANGE_RATE_PRECISION_HIGH;
    }
}

contract PolygonAdapter is Adapter {
    using SafeTransferLib for ERC20;

    IMaticStakeManager private constant MATIC_STAKE_MANAGER =
        IMaticStakeManager(address(0x5e3Ef299fDDf15eAa0432E6e66473ace8c13D908));
    ERC20 private constant POLY = ERC20(address(0x7D1AfA7B718fb893dB30A3aBc0Cfc608AaCfeBB0));

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function isValidator(address validator) public view returns (bool) {
        // Validator must have a validator shares contract
        return address(_getValidatorSharesContract(_getValidatorId(validator))) != address(0);
    }

    function previewDeposit(address, /*validator*/ uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) external view returns (uint256 amount) {
        // get validator for caller (Tenderizer through delegate call)
        address validator = _getValidatorAddress();
        // get the validator shares contract for validator
        uint256 validatorId = _getValidatorId(validator);
        IValidatorShares validatorShares = _getValidatorSharesContract(validatorId);

        DelegatorUnbond memory unbond = validatorShares.unbonds_new(address(this), unlockID);
        // calculate amount of tokens to withdraw by converting shares back into amount
        // See https://github.com/maticnetwork/contracts/blob/main/contracts/staking/validatorShare/ValidatorShare.sol#L281-L282
        amount = unbond.shares * validatorShares.withdrawExchangeRate() / getExchangePrecision(validatorId);
    }

    function unlockMaturity(uint256 unlockID) external view returns (uint256) {
        // Note that this returns the unlockMaturity as a Polygon epoch number in the future
        // It's fairly hard to predict the number of blocks between checkpoints
        // While we could use an historical average, it's better to just return the epoch number for now
        // consumers of this method can still convert it into a block or timestamp if they choose to
        DelegatorUnbond memory u =
            _getValidatorSharesContract(_getValidatorId(_getValidatorAddress())).unbonds_new(address(this), unlockID);
        return u.withdrawEpoch + WITHDRAW_DELAY;
    }

    function unlockTime() external pure override returns (uint256) {
        return WITHDRAW_DELAY;
    }

    function currentTime() external view override returns (uint256) {
        return MATIC_STAKE_MANAGER.epoch();
    }

    function stake(address validator, uint256 amount) external override returns (uint256) {
        // approve tokens
        POLY.safeApprove(address(MATIC_STAKE_MANAGER), amount);

        uint256 validatorId = _getValidatorId(validator);
        IValidatorShares validatorShares = _getValidatorSharesContract(validatorId);

        // calculate minimum amount of voucher shares to mint
        // adjust for integer truncation upon division
        uint256 precision = getExchangePrecision(validatorId);
        uint256 fxRate = validatorShares.exchangeRate();
        uint256 min = amount * precision / fxRate - 1;

        // Mint voucher shares
        validatorShares.buyVoucher(amount, min);
        return amount;
    }

    function unstake(address validator, uint256 amount) external override returns (uint256 unlockID) {
        uint256 validatorId = _getValidatorId(validator);
        IValidatorShares validatorShares = _getValidatorSharesContract(validatorId);

        uint256 precision = getExchangePrecision(validatorId);
        uint256 fxRate = validatorShares.exchangeRate();

        // Unbond tokens
        // calculate max amount of validator shares to burn
        uint256 max = amount * precision / fxRate + 1;
        validatorShares.sellVoucher_new(amount, max);

        return validatorShares.unbondNonces(address(this));
    }

    function withdraw(address validator, uint256 unlockID) external override returns (uint256 amount) {
        uint256 validatorId = _getValidatorId(validator);
        IValidatorShares validatorShares = _getValidatorSharesContract(validatorId);

        DelegatorUnbond memory unbond = validatorShares.unbonds_new(address(this), unlockID);
        // foundation validators (id < 8) don't have slashing enabled
        // see https://github1s.com/maticnetwork/contracts/blob/main/contracts/staking/validatorShare/ValidatorShare.sol#L89-L95
        uint256 fxRate = validatorId >= 8 ? validatorShares.withdrawExchangeRate() : EXCHANGE_RATE_PRECISION;
        amount = unbond.shares * fxRate / getExchangePrecision(validatorId);

        validatorShares.unstakeClaimTokens_new(unlockID);
    }

    function rebase(address validator, uint256 currentStake) external returns (uint256 newStake) {
        uint256 validatorId = _getValidatorId(validator);
        IValidatorShares validatorShares = _getValidatorSharesContract(validatorId);

        // This call will revert if there are no rewards
        // In which case we don't throw, just return the current staked amount.
        // solhint-disable-next-line no-empty-blocks
        try validatorShares.restake() { }
        catch {
            return currentStake;
        }

        // Read new stake
        uint256 shares = validatorShares.balanceOf(address(this));
        uint256 precision = getExchangePrecision(validatorId);
        uint256 fxRate = validatorShares.exchangeRate();
        newStake = shares * fxRate / precision;
    }

    function _getValidatorAddress() internal view returns (address) {
        return ITenderizer(address(this)).validator();
    }

    function _getValidatorId(address validator) internal view returns (uint256) {
        return MATIC_STAKE_MANAGER.getValidatorId(validator);
    }

    function _getValidatorSharesContract(uint256 validatorId) internal view returns (IValidatorShares) {
        return IValidatorShares(MATIC_STAKE_MANAGER.getValidatorContract(validatorId));
    }
}
