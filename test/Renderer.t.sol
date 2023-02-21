// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { Test } from "forge-std/Test.sol";

import { Base64 } from "lib/base64/Base64.sol";
import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ClonesUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { Renderer } from "core/unlocks/Renderer.sol";
import { Unlocks } from "core/unlocks/Unlocks.sol";

// solhint-disable quotes

contract RendererV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  function json(uint256 id) external view returns (string memory) {
    return "test json response";
  }

  ///@dev required by the OZ UUPS module
  function _authorizeUpgrade(address) internal override onlyOwner {}
}

// solhint-disable func-name-mixedcase
// solhint-disable avoid-low-level-calls
contract RendererTest is Test {
  ERC1967Proxy private proxy;
  address private owner = vm.addr(1);
  address private nonAuthorized = vm.addr(2);
  address private tenderizer = vm.addr(3);
  RendererV1 private rendererV1;

  bytes32 internal constant IMPL_SLOT = bytes32(uint256(keccak256("eip1967.proxy.implementation")) - 1);

  function setUp() public {
    vm.startPrank(owner);
    rendererV1 = new RendererV1();
    bytes memory data = abi.encodeWithSignature("initialize()");
    proxy = new ERC1967Proxy(address(rendererV1), data);
    vm.stopPrank();
  }

  function test_implInitializerDisabled() public {
    vm.startPrank(owner);
    vm.expectRevert("Initializable: contract is already initialized");
    rendererV1.initialize();
    vm.stopPrank();
  }

  function test_implInitializerDisabledAfterUpgrade() public {
    vm.startPrank(owner);
    Renderer rendererV2 = new Renderer();
    RendererV1(address(proxy)).upgradeTo(address(rendererV2));
    vm.expectRevert("Initializable: contract is already initialized");
    rendererV2.initialize();
    vm.stopPrank();
  }

  function test_unauthorizedUpgradeAttack() public {
    vm.startPrank(nonAuthorized);

    Renderer rendererV2 = new Renderer();
    ERC1967Proxy proxy2 = new ERC1967Proxy(address(rendererV1), "");

    vm.expectRevert("Function must be called through delegatecall");
    rendererV1.upgradeTo(address(rendererV2));

    vm.expectRevert("Function must be called through active proxy");
    address(proxy2).delegatecall(abi.encodeWithSignature("upgradeTo(address)", address(rendererV2)));

    address implClone = ClonesUpgradeable.clone(address(rendererV1));
    vm.expectRevert("Function must be called through active proxy");
    RendererV1(implClone).upgradeTo(address(rendererV2));

    vm.stopPrank();
  }

  function test_upgradeToFail() public {
    vm.startPrank(nonAuthorized);

    Renderer rendererV2 = new Renderer();

    vm.expectRevert();
    RendererV1(address(proxy)).upgradeTo(address(rendererV2));
    vm.stopPrank();
  }

  function test_upgradeToSuccess() public {
    vm.startPrank(owner);
    Renderer rendererV2 = new Renderer();

    bytes32 proxySlotBefore = vm.load(address(proxy), IMPL_SLOT);
    assertEq(proxySlotBefore, bytes32(uint256(uint160(address(rendererV1)))));

    RendererV1(address(proxy)).upgradeTo(address(rendererV2));

    bytes32 proxySlotAfter = vm.load(address(proxy), IMPL_SLOT);
    assertEq(proxySlotAfter, bytes32(uint256(uint160(address(rendererV2)))));
  }

  function test_proxyImplSlot() public {
    bytes32 proxySlot = vm.load(address(proxy), IMPL_SLOT);
    assertEq(proxySlot, bytes32(uint256(uint160(address(rendererV1)))));
  }

  function test_V1Json() public {
    string memory json = RendererV1(address(proxy)).json(1);
    assertEq(json, "test json response");
  }

  function test_V2Json() public {
    vm.startPrank(owner);
    Renderer rendererV2 = new Renderer();
    RendererV1(address(proxy)).upgradeTo(address(rendererV2));
    vm.stopPrank();
    string memory data = Renderer(address(proxy)).json(1);
    string memory encodedJson = substring(data, 29, bytes(data).length);

    assertEq(
      string(Base64.decode(encodedJson)),
      // solhint-disable-next-line max-line-length
      '{"name": "TenderLock", "description": "TenderLock from https://tenderize.me represents ERC20 tokens during the unbonding period, thus making them tradable. Owning a TenderLock token makes the owner eligible to claim the tokens at the end of the unbonding period.", "image": "data:image/svg+xml;base64,<svg width="290" height="500" viewBox="0 0 290 500" xmlns="http://www.w3.org/2000/svg" xmlns:xlink=\'http://www.w3.org/1999/xlink\'>PHJlY3Qgd2lkdGg9JzI5MHB4JyBoZWlnaHQ9JzUwMHB4JyBmaWxsPScjMDAwMDAwJy8+PHRleHQgeD0nMTAnIHk9JzIwJz50R1JUPC90ZXh0Pjx0ZXh0IHg9IjEwIiB5PSI0MCI+MTAwPC90ZXh0Pjx0ZXh0IHg9IjEwIiB5PSI2MCI+MTAwMDwvdGV4dD48dGV4dCB4PSIxMCIgeT0iODAiPjE8L3RleHQ+PC9zdmc+","attributes":[{"trait_type": "maturity", "value":1000},{"trait_type": "amount", "value":100},{"trait_type": "underlyingToken", "value":"Graph"},{"trait_type": "underlyingSymbol", "value":"GRT"},{"trait_type": "token", "value":"tender GRT"},{"trait_type": "symbol", "value":"tGRT"}]}'
    );
  }

  function getMetadata(uint256 id) public view virtual returns (Unlocks.Metadata memory data) {
    return
      Unlocks.Metadata({
        amount: 100,
        maturity: 1000,
        tokenId: id,
        symbol: "tGRT",
        name: "tender GRT",
        underlyingSymbol: "GRT",
        underlyingName: "Graph"
      });
  }

  function substring(
    string memory str,
    uint256 startIndex,
    uint256 endIndex
  ) public pure returns (string memory) {
    bytes memory strBytes = bytes(str);
    bytes memory result = new bytes(endIndex - startIndex);
    for (uint256 i = startIndex; i < endIndex; i++) {
      result[i - startIndex] = strBytes[i];
    }
    return string(result);
  }
}
