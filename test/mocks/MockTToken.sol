// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TToken } from "core/tendertoken/TToken.sol";
import { FixedPointMathLib } from "solmate/utils/FixedPointMathLib.sol";

contract MockTToken is TToken {
    using FixedPointMathLib for uint256;
    uint256 public totalAssets;

    function name() public pure override returns (string memory) {
        return "MockTenderToken";
    }

    function symbol() public pure override returns (string memory) {
        return "MTT";
    }

    function totalShares() public view returns (uint256) {
        ERC20Data storage s = _loadERC20Slot();
        return s._totalSupply;
    }

    function convertToAssets(uint256 shares) public view override returns (uint256 assets) {
        uint256 _totalShares = totalShares();
        return _totalShares == 0 ? shares : shares.mulDivDown(totalAssets, _totalShares);
    }

    function convertToShares(uint256 assets) public view override returns (uint256 shares) {
        uint256 _totalShares = totalShares();
        return _totalShares == 0 ? assets : assets.mulDivDown(_totalShares, totalAssets);
    }

    function setTotalAssets(uint256 assets) external {
        totalAssets = assets;
    }

    function mint(address receiver, uint256 amount) external {
        _mint(receiver, convertToShares(amount));
        totalAssets += amount;
    }
    
    function burn(address receiver, uint256 amount) external {
        _mint(receiver, convertToShares(amount));
        totalAssets += amount;
    }
}