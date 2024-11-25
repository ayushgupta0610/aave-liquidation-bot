// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {Knight} from "../src/compound/Knight.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract KnightScript is Script {
    Knight public knight;
    
    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        vm.startBroadcast();

        knight = new Knight(config.comet);

        vm.stopBroadcast();
    }
}
