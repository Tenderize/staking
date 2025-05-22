import { ERC1967Proxy } from "openzeppelin-contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { OwnableUpgradeable } from "openzeppelin-contracts-upgradeable/access/OwnableUpgradeable.sol";
import { Initializable } from "openzeppelin-contracts-upgradeable/proxy/utils/Initializable.sol";
import { UUPSUpgradeable } from "openzeppelin-contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

import { MultiValidatorLST } from "core/multi-validator/MultiValidatorLST.sol";
import { UnstakeNFT } from "core/multi-validator/UnstakeNFT.sol";
import { Registry } from "core/registry/Registry.sol";
import { ERC20 } from "solady/tokens/ERC20.sol";

contract MultiValidatorFactory is Initializable, UUPSUpgradeable, OwnableUpgradeable {
    Registry constant registry = Registry(0xa7cA8732Be369CaEaE8C230537Fc8EF82a3387EE);
    address private immutable initialImpl;
    address private immutable initialUnstakeNFTImpl;

    constructor() {
        _disableInitializers();
        initialImpl = address(new MultiValidatorLST{ salt: bytes32(uint256(0)) }(registry));
        initialUnstakeNFTImpl = address(new UnstakeNFT{ salt: bytes32(uint256(0)) }());
    }

    function initialize() external initializer {
        __Ownable_init();
        __UUPSUpgradeable_init();
        transferOwnership(registry.treasury());
    }

    function deploy(address token) external onlyOwner returns (address) {
        string memory symbol = ERC20(token).symbol();
        address stProxy =
            address(new ERC1967Proxy{ salt: keccak256(bytes(string.concat("MultiValidator", symbol))) }(initialImpl, ""));

        address unstProxy = address(
            new ERC1967Proxy{ salt: keccak256(bytes(string.concat("UnstakeNFT", symbol))) }(
                initialUnstakeNFTImpl, abi.encodeCall(UnstakeNFT.initialize, (token, stProxy))
            )
        );

        MultiValidatorLST(stProxy).initialize(token, UnstakeNFT(unstProxy), registry.treasury());

        UnstakeNFT(unstProxy).transferOwnership(registry.treasury());

        return stProxy;
    }

    ///@dev required by the OZ UUPS module
    // solhint-disable-next-line no-empty-blocks
    function _authorizeUpgrade(address) internal override onlyOwner { }
}
