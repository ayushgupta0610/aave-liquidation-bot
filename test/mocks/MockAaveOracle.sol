// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.0;

/**
 * @title MockAaveOracle
 * @author Aave
 * @notice Mocks the basic interface for the Aave Oracle
 */
contract MockAaveOracle {
    mapping(address => uint256) private price;

    function setAssetPrice(address asset, uint256 assetPrice) external {
        price[asset] = assetPrice;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return price[asset];
    }
}
