// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Superman} from "../src/aave/Superman.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract ExecuteLiquidationScript is Script {
    Superman private superman;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Conditional config based on chainId execute liquidation (keeping in mind that on eth the slippage required is 1% and on base 2.5%)

        vm.startBroadcast();

        // flashLoan = new TakeFlashLoan(owner, config.aavePool, poolAddressesProvider, uniswapV2Factory);

        vm.stopBroadcast();
    }
}
