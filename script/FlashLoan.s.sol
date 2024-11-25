// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Script, console} from "forge-std/Script.sol";
import {TakeFlashLoan} from "../src/TakeFlashLoan.sol";
import {HelperConfig} from "./HelperConfig.s.sol";

contract FlashLoanScript is Script {
    TakeFlashLoan public flashLoan;

    function run() public {
        HelperConfig helperConfig = new HelperConfig();
        HelperConfig.NetworkConfig memory config = helperConfig.getConfig();

        // Base network specific addresses
        address owner = 0x47D1111fEC887a7BEb7839bBf0E1b3d215669D86;
        address poolAddressesProvider = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D;
        address uniswapV2Factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;

        vm.startBroadcast();

        flashLoan = new TakeFlashLoan(owner, config.aavePool, poolAddressesProvider, uniswapV2Factory);

        vm.stopBroadcast();
    }
}
