pragma solidity ^0.8.19;

import { ERC20 } from "solmate/tokens/ERC20.sol";

interface ITToken {
    function transferFrom(address, address, uint256) external;
    function transfer(address, uint256) external;
    function convertToShares(uint256) external view returns (uint256);
    function convertToAssets(uint256) external view returns (uint256);
}

contract WtToken is ERC20 {
    event Wrap(address indexed tToken, uint256 amount, uint256 wrappedAmount);
    event Unwrap(address indexed tToken, uint256 amount, uint256 unwrappedAmount);

    ITToken public tToken;

    constructor(address _tToken) ERC20("name", "symbol", 18) {
        tToken = ITToken(_tToken);
    }

    function wrap(uint256 amount) external returns (uint256) {
        uint256 shares = tToken.convertToShares(amount);
        _mint(msg.sender, shares);
        tToken.transferFrom(msg.sender, address(this), amount);
        emit Wrap(address(tToken), amount, shares);
        return shares;
    }

    function unwrap(uint256 amount) external returns (uint256) {
        uint256 amountFromShares = tToken.convertToAssets(amount);
        _burn(msg.sender, amount);
        tToken.transfer(msg.sender, amountFromShares);
        emit Unwrap(address(tToken), amount, amountFromShares);
        return amountFromShares;
    }

    function getWtTokenByTToken(uint256 amount) external view returns (uint256) {
        return tToken.convertToShares(amount);
    }

    function getTTokenByWtToken(uint256 amount) external view returns (uint256) {
        return tToken.convertToAssets(amount);
    }

    function tTokenPerWtToken() external view returns (uint256) {
        return tToken.convertToAssets(1 ether);
    }

    function wtTokenPerTToken() external view returns (uint256) {
        return tToken.convertToShares(1 ether);
    }
}
