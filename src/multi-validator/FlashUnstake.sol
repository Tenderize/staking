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

pragma solidity >=0.8.20;

import { Multicallable } from "solady/utils/Multicallable.sol";
import { SelfPermit } from "core/utils/SelfPermit.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";
import { ERC721Receiver } from "core/utils/ERC721Receiver.sol";
import { SafeTransferLib } from "solady/utils/SafeTransferLib.sol";
import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

interface TenderSwap {
    function quote(address asset, uint256 amount) external view returns (uint256 out, uint256 fee);
    function swap(address asset, uint256 amount, uint256 minOut) external returns (uint256 out, uint256 fee);

    function quoteMultiple(
        address[] calldata assets,
        uint256[] calldata amounts
    )
        external
        view
        returns (uint256 out, uint256 fee);

    function swapMultiple(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256 minOut
    )
        external
        returns (uint256 out, uint256 fee);
}

contract FlashUnstake is ERC721Receiver, Multicallable, SelfPermit {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    error Slippage();

    function flashUnstake(
        address token, // multi validator LST
        address tenderSwap, // TenderSwap address for the asset
        uint256 amount, // amount to flash unstake
        uint256 minOut // min amount to receive
    )
        external
        returns (uint256 out, uint256 fees)
    {
        token.safeTransferFrom(msg.sender, address(this), amount);
        MultiValidatorLST lst = MultiValidatorLST(token);
        (address[] memory tTokens, uint256[] memory amounts) = lst.unwrap(amount, amount.mulWad(lst.exchangeRate()));

        uint256 l = tTokens.length;

        if (l == 0) revert();

        if (l == 1) {
            uint256 bal = ERC20(tTokens[0]).balanceOf(address(this));
            amount = bal < amounts[0] ? bal : amounts[0];
            tTokens[0].safeApprove(tenderSwap, amount);
            (out, fees) = TenderSwap(tenderSwap).swap(tTokens[0], amount, minOut);
        } else {
            uint256 bal = ERC20(tTokens[0]).balanceOf(address(this));
            for (uint256 i = 0; i < l; ++i) {
                amounts[i] = bal < amounts[i] ? bal : amounts[i];
                tTokens[i].safeApprove(tenderSwap, amounts[i]);
            }
            (out, fees) = TenderSwap(tenderSwap).swapMultiple(tTokens, amounts, minOut);
        }
        if (out < minOut) revert Slippage();
        lst.token().safeTransfer(msg.sender, out);
    }

    function flashUnstakeQuote(
        address token,
        address tenderSwap,
        uint256 amount
    )
        external
        view
        returns (uint256 out, uint256 fees)
    {
        (address[] memory tTokens, uint256[] memory amounts) = MultiValidatorLST(token).previewUnwrap(amount);
        uint256 l = tTokens.length;

        if (l == 0) revert();
        if (l == 1) {
            (out, fees) = TenderSwap(tenderSwap).quote(tTokens[0], amounts[0]);
        } else {
            (out, fees) = TenderSwap(tenderSwap).quoteMultiple(tTokens, amounts);
        }
    }
}
