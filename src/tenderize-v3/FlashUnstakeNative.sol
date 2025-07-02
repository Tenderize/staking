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
import { MultiValidatorLST } from "core/tenderize-v3/multi-validator/MultiValidatorLST.sol";
import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";

interface TenderSwap {
    function quote(address asset, uint256 amount) external view returns (uint256 out, uint256 fee);
    function swap(address asset, uint256 amount, uint256 minOut) external payable returns (uint256 out, uint256 fee);

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
        payable
        returns (uint256 out, uint256 fee);
}

contract FlashUnstakeNative is ERC721Receiver, Multicallable, SelfPermit {
    using SafeTransferLib for address;
    using FixedPointMathLib for uint256;

    error Slippage();
    error TransferFailed();

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
        MultiValidatorLST lst = MultiValidatorLST(payable(token));
        (address payable[] memory tTokens, uint256[] memory amounts) = lst.unwrap(amount, amount.mulWad(lst.exchangeRate()));

        uint256 l = tTokens.length;

        if (l == 0) revert();

        if (l == 1) {
            uint256 bal = address(this).balance;
            amount = bal < amounts[0] ? bal : amounts[0];
            (out, fees) = TenderSwap(tenderSwap).swap{ value: amount }(address(tTokens[0]), amount, minOut);
        } else {
            uint256 bal = address(this).balance;
            for (uint256 i = 0; i < l; ++i) {
                amounts[i] = bal < amounts[i] ? bal : amounts[i];
            }
            // Convert payable array to address array
            address[] memory assets = new address[](l);
            for (uint256 i = 0; i < l; ++i) {
                assets[i] = address(tTokens[i]);
            }
            (out, fees) = TenderSwap(tenderSwap).swapMultiple{ value: address(this).balance }(assets, amounts, minOut);
        }
        if (out < minOut) revert Slippage();

        // Transfer native tokens back to sender
        (bool success,) = payable(msg.sender).call{ value: out }("");
        if (!success) revert TransferFailed();
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
        (address payable[] memory tTokens, uint256[] memory amounts) = MultiValidatorLST(payable(token)).previewUnwrap(amount);
        uint256 l = tTokens.length;

        if (l == 0) revert();
        if (l == 1) {
            (out, fees) = TenderSwap(tenderSwap).quote(address(tTokens[0]), amounts[0]);
        } else {
            // Convert payable array to address array
            address[] memory assets = new address[](l);
            for (uint256 i = 0; i < l; ++i) {
                assets[i] = address(tTokens[i]);
            }
            (out, fees) = TenderSwap(tenderSwap).quoteMultiple(assets, amounts);
        }
    }

    // Handle native token receives
    receive() external payable {
        // Allow contract to receive native tokens
    }
}
