// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ClonesUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import { Renderer } from "core/unlocks/Renderer.sol";
import "forge-std/Test.sol";

contract RendererV1 is Initializable, UUPSUpgradeable, OwnableUpgradeable {
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize() public initializer {
    __Ownable_init();
  }

  function json(Renderer.Data memory data) external view returns (string memory) {
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
    string memory json = RendererV1(address(proxy)).json(getTestData(tenderizer, 1));
    assertEq(json, "test json response");
  }

  function test_V2Json() public {
    vm.startPrank(owner);
    Renderer rendererV2 = new Renderer();
    RendererV1(address(proxy)).upgradeTo(address(rendererV2));
    vm.stopPrank();
    string memory json = RendererV1(address(proxy)).json(getTestData(tenderizer, 1));
    assertEq(
      json,
      // solhint-disable max-line-length
      "data:application/json;base64,eyJuYW1lIjogIlRlbmRlckxvY2siLCAiZGVzY3JpcHRpb24iOiAiVGVuZGVyTG9jayBmcm9tIGh0dHBzOi8vdGVuZGVyaXplLm1lIHJlcHJlc2VudHMgRVJDMjAgdG9rZW5zIGR1cmluZyB0aGUgdW5ib25kaW5nIHBlcmlvZCwgdGh1cyBtYWtpbmcgdGhlbSB0cmFkYWJsZS4gT3duaW5nIGEgVGVuZGVyTG9jayB0b2tlbiBtYWtlcyB0aGUgb3duZXIgZWxpZ2libGUgdG8gY2xhaW0gdGhlIHRva2VucyBhdCB0aGUgZW5kIG9mIHRoZSB1bmJvbmRpbmcgcGVyaW9kLiIsICJpbWFnZSI6ICJkYXRhOmltYWdlL3N2Zyt4bWw7YmFzZTY0LDxzdmcgd2lkdGg9IjI5MCIgaGVpZ2h0PSI1MDAiIHZpZXdCb3g9IjAgMCAyOTAgNTAwIiB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHhtbG5zOnhsaW5rPSdodHRwOi8vd3d3LnczLm9yZy8xOTk5L3hsaW5rJz5QSEpsWTNRZ2QybGtkR2c5SnpJNU1IQjRKeUJvWldsbmFIUTlKelV3TUhCNEp5Qm1hV3hzUFNjak1EQXdNREF3Snk4K1BIUmxlSFFnZUQwbk1UQW5JSGs5SnpJd0p6NTBSMUpVUEM5MFpYaDBQangwWlhoMElIZzlJakV3SWlCNVBTSTBNQ0krTVRBd1BDOTBaWGgwUGp4MFpYaDBJSGc5SWpFd0lpQjVQU0kyTUNJK01UQXdNRHd2ZEdWNGRENDhkR1Y0ZENCNFBTSXhNQ0lnZVQwaU9EQWlQalEzTURjMU56TXlNak13TnpNM05EVTFNak01TmpnME1EVTRNRE14TlRJNU5EQXpOemt4TWpJNE1EYzROemMzTlRreU16RTNPRGMwT0RjNU16ZzNNalF6TWpreU5qVTFOakUyTURBeFBDOTBaWGgwUGp3dmMzWm5QZz09IiwiYXR0cmlidXRlcyI6W3sidHJhaXRfdHlwZSI6ICJtYXR1cml0eSIsICJ2YWx1ZSI6MTAwMH0seyJ0cmFpdF90eXBlIjogImFtb3VudCIsICJ2YWx1ZSI6MTAwfSx7InRyYWl0X3R5cGUiOiAidW5kZXJseWluZ1Rva2VuIiwgInZhbHVlIjoiR3JhcGgifSx7InRyYWl0X3R5cGUiOiAidW5kZXJseWluZ1N5bWJvbCIsICJ2YWx1ZSI6IkdSVCJ9LHsidHJhaXRfdHlwZSI6ICJ0b2tlbiIsICJ2YWx1ZSI6InRlbmRlciBHUlQifSx7InRyYWl0X3R5cGUiOiAic3ltYm9sIiwgInZhbHVlIjoidEdSVCJ9XX0="
    );
  }

  function getTestData(address _tenderizer, uint96 id) internal view virtual returns (Renderer.Data memory data) {
    return
      Renderer.Data({
        amount: 100,
        maturity: 1000,
        tokenId: uint256(bytes32(abi.encodePacked(_tenderizer, id))),
        symbol: "tGRT",
        name: "tender GRT",
        underlyingSymbol: "GRT",
        underlyingName: "Graph"
      });
  }
}
