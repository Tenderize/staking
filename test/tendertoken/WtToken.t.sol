pragma solidity >=0.8.19;

import { Test, console } from "forge-std/Test.sol";
import { VmSafe } from "forge-std/Vm.sol";

import { Wrapper } from "core/tendertoken/Wrapper.sol";
import { WtToken } from "core/tendertoken/wTToken.sol";
import { Registry } from "core/registry/Registry.sol";
import { TToken } from "core/tendertoken/TToken.sol";
import { ERC20 } from "solmate/tokens/ERC20.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";

contract WrapperTest is Test {
    address tenderizer = 0x4b0e5E54Df6d5eCcC7B2F838982411DC93253dAf;
    address user = 0xF9CcA0b41063B611Dd210250ec9754007e87de6f;

    Wrapper wrapper;

    function setUp() public {
        vm.createSelectFork(vm.envString("ARBITRUM_RPC"));
        wrapper = new Wrapper();

        // make sure we rebase before we do anything
        Tenderizer(payable(tenderizer)).rebase();
    }

    function test_wrap_unwrap() public {
        uint256 amount = 100 ether;
        // no current wrapper
        assertEq(wrapper.wrappedToken(tenderizer), address(0));
        // wrap
        vm.startPrank(user);

        uint256 expectedAmount = TToken(tenderizer).convertToShares(amount);
        TToken(tenderizer).approve(address(wrapper), amount);
        (address wTToken, uint256 wrappedAmount) = wrapper.wrap(tenderizer, amount);
        vm.stopPrank();

        assertEq(ERC20(wTToken).balanceOf(user), expectedAmount);
        assertEq(wrappedAmount, expectedAmount);

        // unwrap
        vm.startPrank(user);
        ERC20(wTToken).approve(address(wrapper), wrappedAmount);
        (address tToken, uint256 unwrappedAmount) = wrapper.unwrap(wTToken, wrappedAmount);
        vm.stopPrank();
        assertEq(tToken, tenderizer);
        assertEq(unwrappedAmount, amount - 1); // rounding error
    }

    function test_wrap_notTToken() public {
        vm.expectRevert(abi.encodeWithSelector(Wrapper.NotTToken.selector));
        wrapper.wrap(user, 100 ether);
    }

    function test_unwrap_notwTToken() public {
        vm.expectRevert();
        wrapper.unwrap(user, 100 ether);
    }
}
