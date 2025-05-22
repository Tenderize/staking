pragma solidity ^0.8.19;

import { WtToken } from "core/tendertoken/wTToken.sol";
import { Registry } from "core/registry/Registry.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";

Registry constant REGISTRY = Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE);

contract Wrapper {
    error NotTToken();

    event NewWrappedToken(address tToken, address wtToken);

    mapping(address tToken => WtToken wtToken) private wrappers;

    function createWrappedToken(address tToken) public {
        if (address(wrappers[tToken]) != address(0)) revert();
        if (!REGISTRY.isTenderizer(tToken)) revert NotTToken();
        WtToken wtToken = new WtToken(tToken);
        wrappers[tToken] = wtToken;
        emit NewWrappedToken(tToken, address(wtToken));
    }

    function wrap(address tToken, uint256 amount) external returns (address, uint256) {
        WtToken wtToken = wrappers[tToken];
        if (address(wtToken) == address(0)) createWrappedToken(tToken);

        ERC20(tToken).transferFrom(msg.sender, address(this), amount);
        ERC20(tToken).approve(address(wtToken), amount);

        uint256 wrapped = wtToken.wrap(amount);
        ERC20(wtToken).transfer(msg.sender, wrapped);
        return (address(wtToken), wrapped);
    }

    function unwrap(address wtToken, uint256 amount) external returns (address, uint256) {
        ERC20(wtToken).transferFrom(msg.sender, address(this), amount);
        uint256 unwrapped = WtToken(wtToken).unwrap(amount);
        address tToken = address(WtToken(wtToken).tToken());
        ERC20(tToken).transfer(msg.sender, unwrapped);
        return (tToken, unwrapped);
    }

    function wrappedToken(address tToken) external view returns (address) {
        return address(wrappers[tToken]);
    }
}
