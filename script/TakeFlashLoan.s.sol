// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Script} from "forge-std/Script.sol";
import {TakeFlashLoan} from "../src/TakeFlashLoan.sol";
import {console2} from "forge-std/console2.sol";

contract TakeFlashLoanScript is Script {
    // Example tokens (Base)
    address constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address constant WETH = 0x4200000000000000000000000000000000000006;

    function run() external {
        // Start broadcasting transactions
        vm.startBroadcast();

        // Make use of a FlashLoan contract instance (on Base)
        address flashLoanAddress = 0xf7FBd3c0BEe42c35EcDEdA15f7BaBf6694F198f6;
        TakeFlashLoan flashLoan = TakeFlashLoan(payable(flashLoanAddress));

        // Example flash loan parameters
        uint256 flashLoanAmount = 2 ether; // 2 ether
        uint256 minAmountOut = 6000 * 1e6; // Minimum expected output (accounting for slippage)
        uint256 expectedAmountOut = 7000 * 1e6; // Expected output after swap

        // Take flash loan
        flashLoan.takeFlashLoan(
            WETH, // token to borrow
            flashLoanAmount, // amount to borrow
            USDC, // token to swap to
            minAmountOut, // minimum amount to receive
            expectedAmountOut // expected amount to receive
        );

        vm.stopBroadcast();

        console2.log("Flash loan executed");
        console2.log("Flash Loan contract deployed at:", address(flashLoan));
    }
}
