// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Superman} from "../src/aave/Superman.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract SupermanScript is Script {
    Superman public superman;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();

        superman = new Superman(config.account, config.aavePool, config.poolAddressesProvider);

        vm.stopBroadcast();
    }
}
