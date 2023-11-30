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

import { ERC20 } from "solmate/tokens/ERC20.sol";
import { SafeTransferLib } from "solmate/utils/SafeTransferLib.sol";

import { Adapter } from "core/adapters/Adapter.sol";
import { ILivepeerBondingManager, ILivepeerRoundsManager } from "core/adapters/interfaces/ILivepeer.sol";
import { ISwapRouter } from "core/adapters/interfaces/ISwapRouter.sol";
import { IWETH9 } from "core/adapters/interfaces/IWETH9.sol";
import { IERC165 } from "core/interfaces/IERC165.sol";
import { TWAP } from "core/utils/TWAP.sol";

contract LivepeerAdapter is Adapter {
    using SafeTransferLib for ERC20;

    struct Storage {
        uint256 lastRebaseRound;
    }

    uint256 private constant STORAGE = uint256(keccak256("xyz.tenderize.livepeer.adapter.storage.location")) - 1;

    function _loadStorage() internal pure returns (Storage storage $) {
        uint256 slot = STORAGE;

        // solhint-disable-next-line no-inline-assembly
        assembly {
            $.slot := slot
        }
    }

    ILivepeerBondingManager private constant LIVEPEER = ILivepeerBondingManager(0x35Bcf3c30594191d53231E4FF333E8A770453e40);
    ILivepeerRoundsManager private constant LIVEPEER_ROUNDS = ILivepeerRoundsManager(0xdd6f56DcC28D3F5f27084381fE8Df634985cc39f);
    ERC20 private constant LPT = ERC20(0x289ba1701C2F088cf0faf8B3705246331cB8A839);
    IWETH9 private constant WETH = IWETH9(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
    ISwapRouter private constant UNISWAP_ROUTER = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    address private constant UNI_POOL = 0x4fD47e5102DFBF95541F64ED6FE13d4eD26D2546;
    uint24 private constant UNISWAP_POOL_FEE = 10_000;
    uint256 private constant ETH_THRESHOLD = 1e16; // 0.01 ETH
    uint32 private constant TWAP_INTERVAL = 36_000;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return interfaceId == type(Adapter).interfaceId || interfaceId == type(IERC165).interfaceId;
    }

    function previewDeposit(uint256 assets) external pure returns (uint256) {
        return assets;
    }

    function previewWithdraw(uint256 unlockID) external view returns (uint256 amount) {
        (amount,) = LIVEPEER.getDelegatorUnbondingLock(address(this), unlockID);
    }

    function unlockMaturity(uint256 unlockID) external view returns (uint256 maturity) {
        // calculate unlock maturity in block number
        // in Livepeer this is expressed in rounds with a fixed amount of blocks
        // roundLength = n
        // currentRound = r
        // withdrawRound = w
        // blockRemainingInCurrentRound = b = roundLength - (block.number - currentRoundStartBlock)
        // maturity = n*(w - r - 1) + b
        (, uint256 withdrawRound) = LIVEPEER.getDelegatorUnbondingLock(address(this), unlockID);
        uint256 currentRound = LIVEPEER_ROUNDS.currentRound();
        uint256 roundLength = LIVEPEER_ROUNDS.roundLength();
        uint256 currentRoundStartBlock = LIVEPEER_ROUNDS.currentRoundStartBlock();
        uint256 blockRemainingInCurrentRound = roundLength - (block.number - currentRoundStartBlock);
        if (withdrawRound > currentRound) {
            maturity = roundLength * (withdrawRound - currentRound - 1) + blockRemainingInCurrentRound;
        }
    }

    function unlockTime() external view override returns (uint256) {
        return LIVEPEER_ROUNDS.roundLength() * LIVEPEER.unbondingPeriod();
    }

    function currentTime() external view override returns (uint256) {
        return block.number;
    }

    function stake(address validator, uint256 amount) public {
        LPT.approve(address(LIVEPEER), amount);
        LIVEPEER.bond(amount, validator);
    }

    function unstake(address, /*validator*/ uint256 amount) external returns (uint256 unlockID) {
        // returns the *next* Livepeer unbonding lock ID for the delegator
        // this will be the `unlockID` after calling unbond
        (,,,,,, unlockID) = LIVEPEER.getDelegator(address(this));
        LIVEPEER.unbond(amount);
    }

    function withdraw(address, /*validator*/ uint256 unlockID) external returns (uint256 amount) {
        (amount,) = LIVEPEER.getDelegatorUnbondingLock(address(this), unlockID);
        LIVEPEER.withdrawStake(unlockID);
    }

    function rebase(address validator, uint256 currentStake) external returns (uint256 newStake) {
        uint256 currentRound = LIVEPEER_ROUNDS.currentRound();

        Storage storage $ = _loadStorage();
        if ($.lastRebaseRound < currentRound) {
            return currentStake;
        }

        $.lastRebaseRound = currentRound;

        _livepeerClaimFees();

        // restake
        uint256 amount = LPT.balanceOf(address(this));
        if (amount != 0) {
            stake(validator, amount);
        }

        // Read new stake
        newStake = LIVEPEER.pendingStake(address(this), 0);
    }

    function isValidator(address validator) public view override returns (bool) {
        return LIVEPEER.isRegisteredTranscoder(validator);
    }

    /// @notice function for swapping ETH fees to LPT
    function _livepeerClaimFees() internal {
        // get pending fees
        uint256 pendingFees;
        if ((pendingFees = LIVEPEER.pendingFees(address(this), 0)) < ETH_THRESHOLD) return;

        // withdraw fees
        LIVEPEER.withdrawFees(payable(address(this)), pendingFees);
        // get ETH balance
        uint256 ethBalance = address(this).balance;
        // convert fees to WETH
        WETH.deposit{ value: ethBalance }();
        ERC20(address(WETH)).safeApprove(address(UNISWAP_ROUTER), ethBalance);
        // Calculate Slippage Threshold
        uint256 twapPrice = TWAP.getInversePriceX96(TWAP.getPriceX96(TWAP.getSqrtTwapX96(UNI_POOL, TWAP_INTERVAL)));
        uint256 amountOut = ethBalance * twapPrice >> 96;
        // Create initial params for swap
        ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
            tokenIn: address(WETH),
            tokenOut: address(address(LPT)),
            fee: UNISWAP_POOL_FEE,
            recipient: address(this),
            deadline: block.timestamp,
            amountIn: ethBalance,
            amountOutMinimum: amountOut * 897 / 1000, // 10% slippage threshold + 0.3% fee
            sqrtPriceLimitX96: 0
        });

        // execute swap
        UNISWAP_ROUTER.exactInputSingle(params);
    }
}
