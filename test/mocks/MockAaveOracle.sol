// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

import {IAaveOracle, IPoolAddressesProvider} from "../../src/interfaces/IAaveOracle.sol";

/**
 * @title MockAaveOracle
 * @author Aave
 * @notice Mocks the basic interface for the Aave Oracle
 */
contract MockAaveOracle is IAaveOracle {
    mapping(address => uint256) private prices;

    function setAssetPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return prices[asset];
    }

    function BASE_CURRENCY() external view override returns (address) {}

    function BASE_CURRENCY_UNIT() external pure override returns (uint256) {
        return 1e8; // For USD based pricing
    }

    function getAssetsPrices(address[] calldata assets) external view override returns (uint256[] memory) {
        uint256[] memory _prices = new uint256[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            _prices[i] = prices[assets[i]];
        }
        return _prices;
    }

    function ADDRESSES_PROVIDER() external view override returns (IPoolAddressesProvider) {}

    function setAssetSources(address[] calldata assets, address[] calldata sources) external override {}

    function setFallbackOracle(address fallbackOracle) external override {}

    function getSourceOfAsset(address asset) external view override returns (address) {}

    function getFallbackOracle() external view override returns (address) {}
}
