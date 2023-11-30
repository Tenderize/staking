// SPDX-FileCopyrightText: 2021 Tenderize <info@tenderize.me>

// SPDX-License-Identifier: MIT

// solhint-disable func-name-mixedcase

pragma solidity >=0.8.19;

struct DelegatorUnbond {
    uint256 shares;
    uint256 withdrawEpoch;
}

interface IMaticStakeManager {
    function getValidatorId(address user) external view returns (uint256);
    function getValidatorContract(uint256 validatorId) external view returns (address);
    function epoch() external view returns (uint256);
}

interface IValidatorShares {
    function owner() external view returns (address);

    function restake() external;

    function buyVoucher(uint256 _amount, uint256 _minSharesToMint) external;

    function sellVoucher_new(uint256 claimAmount, uint256 maximumSharesToBurn) external;

    function unstakeClaimTokens_new(uint256 unbondNonce) external;

    function exchangeRate() external view returns (uint256);

    function validatorId() external view returns (uint256);

    function balanceOf(address) external view returns (uint256);

    function unbondNonces(address) external view returns (uint256);

    function withdrawExchangeRate() external view returns (uint256);

    function unbonds_new(address, uint256) external view returns (DelegatorUnbond memory);
}
