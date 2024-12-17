// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console2} from "forge-std/Script.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract HelperConfig is Script {
    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/
    error HelperConfig__InvalidChainId();

    /*//////////////////////////////////////////////////////////////
                                 TYPES
    //////////////////////////////////////////////////////////////*/
    struct NetworkConfig {
        address aavePool;
        address poolAddressesProvider;
        address comet;
        address usdc;
        address weth;
        address aaveOracle;
        address routerV2;
        address account;
    }

    /*//////////////////////////////////////////////////////////////
                            STATE VARIABLES
    //////////////////////////////////////////////////////////////*/
    uint256 constant ETH_SEPOLIA_CHAIN_ID = 11155111;
    uint256 constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 constant BASE_MAINNET_CHAIN_ID = 8453;

    // Update the BURNER_WALLET to your burner wallet!
    address constant BURNER_WALLET = 0x47D1111fEC887a7BEb7839bBf0E1b3d215669D86;
    // address constant FOUNDRY_DEFAULT_WALLET = 0x1804c8AB1F12E6bbf3894d4083f33e07309d1f38;
    // address constant ANVIL_DEFAULT_ACCOUNT = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266;

    NetworkConfig public localNetworkConfig;
    mapping(uint256 chainId => NetworkConfig) public networkConfigs;

    /*//////////////////////////////////////////////////////////////
                               FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    constructor() {
        networkConfigs[ETH_SEPOLIA_CHAIN_ID] = getEthSepoliaConfig();
        networkConfigs[ETH_MAINNET_CHAIN_ID] = getEthMainnetConfig();
        networkConfigs[BASE_MAINNET_CHAIN_ID] = getBaseMainnetConfig();
    }

    function getConfig() public view returns (NetworkConfig memory) {
        return getConfigByChainId(block.chainid);
    }

    function getConfigByChainId(uint256 endpointId) public view returns (NetworkConfig memory) {
        if (networkConfigs[endpointId].aavePool != address(0)) {
            return networkConfigs[endpointId];
        } else {
            revert HelperConfig__InvalidChainId();
        }
    }

    /*//////////////////////////////////////////////////////////////
                                CONFIGS
    //////////////////////////////////////////////////////////////*/
    function getEthSepoliaConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            aavePool: 0x6Ae43d3271ff6888e7Fc43Fd7321a503ff738951,
            poolAddressesProvider: 0x012bAC54348C0E635dCAc9D5FB99f06F24136C9A,
            comet: 0xAec1F48e02Cfb822Be958B68C7957156EB3F0b6e,
            usdc: 0x94a9D9AC8a22534E3FaCa9F4e7F2E2cf85d5E4C8, // usdc for comet: 0x2F6F07CDcf3588944Bf4C42aC74ff24bF56e7590
            weth: 0xC558DBdd856501FCd9aaF1E62eae57A9F0629a3c,
            routerV2: address(0),
            aaveOracle: 0x2da88497588Bf89c8C5b55D7C7622B3a9cA4a0fA,
            account: BURNER_WALLET
        });
    }

    function getEthMainnetConfig() public pure returns (NetworkConfig memory) {
        // This is v7
        return NetworkConfig({
            aavePool: 0x87870Bca3F3fD6335C3F4ce8392D69350B4fA4E2,
            poolAddressesProvider: 0x2f39d218133AFaB8F2B819B1066c7E434Ad94E9e,
            comet: 0xc3d688B66703497DAA19211EEdff47f25384cdc3,
            usdc: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            weth: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
            routerV2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D,
            aaveOracle: 0x54586bE62E3c3580375aE3723C145253060Ca0C2,
            account: BURNER_WALLET
        });
    }

    function getBaseMainnetConfig() public pure returns (NetworkConfig memory) {
        return NetworkConfig({
            aavePool: 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5,
            poolAddressesProvider: 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D,
            comet: 0xb125E6687d4313864e53df431d5425969c15Eb2F,
            usdc: 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913,
            weth: 0x4200000000000000000000000000000000000006,
            routerV2: 0x4752ba5DBc23f44D87826276BF6Fd6b1C372aD24,
            aaveOracle: 0x2Cc0Fc26eD4563A5ce5e8bdcfe1A2878676Ae156,
            account: BURNER_WALLET
        });
    }
}
