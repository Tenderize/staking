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

// solhint-disable no-console

pragma solidity >=0.8.19;

import { Script, console2 } from "forge-std/Script.sol";
import { MockERC20 } from "solmate/test/utils/mocks/MockERC20.sol";
import { StakingXYZ } from "../test/helpers/StakingXYZ.sol";
import { XYZAdapter } from "../test/helpers/XYZAdapter.sol";
import { Registry } from "core/registry/Registry.sol";
import { Tenderizer } from "core/tenderizer/Tenderizer.sol";
import { Factory } from "core/factory/Factory.sol";

contract XYZ_Data is Script {
    bytes32 private constant salt = 0x0;

    address constant LPT = 0x042Dd916727378Cf913B7719a5071D5789139feb;
    address constant GRT = 0xdcfF31D3311BAbf2f14EC947BdAcE2404D3C922f;
    address constant POL = 0x3e278E3fEE9A2E82437d9eAa0a7836095CbD8070;

    address[] livepeer = [
        0x07CA020fDDE5c57C1C3A783befdb08929cf77fec, // coaction
        0x47A907a0BD1627D71cD14430A721D1550d6D6f58, // nightnode
        0xBD677e96a755207D348578727AA57A512C2022Bd, // pixelfield
        0xb1c579757622D8Ca7bD42542cb0325de1C8E1F8d, // video-miner.eth
        0x10b21af759129F32C6064ADfb85d3eA2a8C0209c, // ruthlessmango.eth
        0x269EBeee083CE6f70486a67dC8036A889bF322A9, // thomasblock.eth
        0xf4e8Ef0763BCB2B1aF693F5970a00050a6aC7E1B, // livepool.eth
        0x847791cBF03be716A7fe9Dc8c9Affe17Bd49Ae5e, // captain-stronk.eth
        0xBe8770603dAf200b1Fa136aD354BA854928e602B, // titan node
        0x9D61ae5875E89036FBf6059f3116d01a22ACe3C8, // authority-null
        0x10e0A91E652b05e9C7449ff457Cf2E96C3037fB7, // interprtr.eth
        0xdc28F2842810D1a013aD51DE174D02eABA192dC7 // pon-node.eth
    ];

    address[] graph = [
        0x87Eba079059B75504c734820d6cf828476754B83, //data nexus
        0x07CA020fDDE5c57C1C3A783befdb08929cf77fec, // coaction
        0x326c584E0F0eaB1f1f83c93CC6Ae1aCC0feba0Bc, // graphtronauts
        0xa3276E7ab0a162F6A3b5aA6B3089aCcBAA65d12e, // stakesquid
        0x6f8a032B4b1Ee622EF2F0fC091bdbB98CFAE81A3, // semiotic
        0x1A99DD7d916117a523f3CE6510dcFD6BcEAB11E7, // p-ops.eth
        0xDFE6Ad10265AfC05831b332FDA6F5Bc1Ad9d79ce, // p2p.org
        0x8842ea85732F94Feeb9cF1Ccc7D357C63658E7A4, // chorus-one
        0x43cd17fa4c21440d71d34061F9A6AA9f99093049, // chainflow
        0x048cFedf907c4C9dDD11ff882380906E78E84BbE, // blockdaemon
        0x0fd8FD1dC8162148cb9413062FE6C6B144335Dbf, // protofire
        0xc35649Ae99Be820c7B200a0ADD09b96D7032d232, // hashquark
        0x1EFEcb61A2f80Aa34d3b9218B564a64D05946290, // figment
        0x62A0BD1d110FF4E5b793119e95Fc07C9d1Fc8c4a, // ellipfra
        0xef46D5fe753c988606E6F703260D816AF53B03EB, // staked
        0x7DDf0C8cB0167870Bf7CC5368792C93AEEb15430, // stake2earn
        0x0b9d582B7FDD387bA13Ad7f453d49aF255a8ED5E, // Dapplooker
        0x269EBeee083CE6f70486a67dC8036A889bF322A9, // thomasblock.eth
        0x1B7E0068cA1d7929c8c56408d766e1510E54d98D // suntzu.eth
    ];

    address[] polygon = [
        0x127685D6dD6683085Da4B6a041eFcef1681E5C9C, // vault staking
        0x959A4D857b7071c38878BEb9DC77051b5Fed1DFd, // girnaar
        0x87Eba079059B75504c734820d6cf828476754B83, // data nexus
        0x62fB676db64f87fd1602048106476C6036D44c92, // blocks united
        0x8842ea85732F94Feeb9cF1Ccc7D357C63658E7A4, // chorus-one
        0x9eaD03F7136Fc6b4bDb0780B00a1c14aE5A8B6d0, // luganodes
        0x742d13F0b2A19C823bdd362b16305e4704b97A38, // infStones
        0xF0245F6251Bef9447A08766b9DA2B07b28aD80B0, // allnodes
        0x048cFedf907c4C9dDD11ff882380906E78E84BbE, // blockdaemon
        0xb95D435df3f8b2a8D8b9c2b7c8766C9ae6ED8cc9, // everstake
        0x3A9DF5dFcB4cC102ce20D40434A2b1BacA9eAfD3, // atlas staking
        0x1EFEcb61A2f80Aa34d3b9218B564a64D05946290, // figment
        0xC6869257205e20c2A43CB31345DB534AECB49F6E, // staking4all
        0x43cd17fa4c21440d71d34061F9A6AA9f99093049, // chainflow
        0xef46D5fe753c988606E6F703260D816AF53B03EB, // staked
        0xa8B52F02108AA5F4B675bDcC973760022D7C6020, // twinstake
        0xDFE6Ad10265AfC05831b332FDA6F5Bc1Ad9d79ce, // p2p.org
        0x414B4b5a2A0e303B89360EdA83598aB7702EAe04, // Vader73
        0x6b2Ed7E4b12A544ca7D215fED85dC16240D64aea, // defimatic
        0xc35649Ae99Be820c7B200a0ADD09b96D7032d232, // hashquark
        0x8E9700392F9246a6c5B32eE3EcEF586F156Ed683, // newroad network
        0xbc6044f4a1688D8B8596A9f7D4659e09985EeBE6 // stake.fish
    ];

    function run() public {
        uint256 privKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(privKey);

        // address tenderizer_1 = 0x35D2BC5Fc0884a7A24E9B1D723A4d99922d788EB;
        // address tenderizer_2 = 0xD58Fed21106A046093086903909478AD96D310a8;
        // address tenderizer_3 = 0x2eaC4210B90D13666f7E88635096BdC17C51FB70;
        // XYZ.approve(tenderizer_1, 10_000_000_000 ether);
        // XYZ.approve(tenderizer_2, 10_000_000_000 ether);
        // XYZ.approve(tenderizer_3, 10_000_000_000 ether);

        // Tenderizer(tenderizer_1).deposit(me, 35_983 ether);
        // Tenderizer(tenderizer_2).deposit(me, 12_821 ether);
        // Tenderizer(tenderizer_3).deposit(me, 5123 ether);

        // Tenderizer(tenderizer_1).unlock(1202 ether);

        address factory = vm.envAddress("FACTORY");
        address asset = vm.envAddress("ASSET");
        address[] memory validators;

        if (asset == LPT) validators = livepeer;
        if (asset == GRT) validators = graph;
        if (asset == POL) validators = polygon;

        for (uint256 i = 0; i < validators.length; i++) {
            address t = Factory(factory).newTenderizer(asset, validators[i]);
            console2.log("Validator: %s", validators[i]);
            console2.log("Tenderizer: %s", t);
        }
    }
}
