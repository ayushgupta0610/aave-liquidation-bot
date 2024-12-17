// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Superman} from "../src/aave/Superman.sol";
import {HelperConfig} from "./HelperConfig.s.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IPool} from "../src/interfaces/IPool.sol";

contract ExecuteLiquidationScript is Script {
    uint256 private constant ETH_MAINNET_CHAIN_ID = 1;
    uint256 private constant BASE_MAINNET_CHAIN_ID = 8453;

    Superman private superman;
    IERC20 private collateralToken;
    IERC20 private debtToken;
    IPool private pool;
    uint256 private slippageFactor;
    address private user;

    function run() public {
        // Get user address from command line argument
        user = vm.envAddress("LIQUIDATION_USER");
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Conditional config based on chainId execute liquidation (keeping in mind that on eth the slippage required is 1% and on base 2.5%)
        if (block.chainid == ETH_MAINNET_CHAIN_ID) {
            slippageFactor = 100;
        } else if (block.chainid == BASE_MAINNET_CHAIN_ID) {
            slippageFactor = 250;
        }
        collateralToken = IERC20(config.weth);
        debtToken = IERC20(config.usdc);
        pool = IPool(config.aavePool);

        vm.startBroadcast();
        // Get total debt
        (, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);
        // Try to liquidate 50% of the debt (should be capped at 50%)
        uint256 debtToCover = (totalDebtBase * 50) / 100;

        // debtToken.approve(address(superman), debtToCover); // TODO: Do it before running this script (to be executed by the liquidator)
        superman.liquidate(address(collateralToken), address(debtToken), user, debtToCover, false, slippageFactor);
        vm.stopBroadcast();
    }
}
