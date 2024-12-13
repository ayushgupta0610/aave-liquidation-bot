// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {console} from "forge-std/Test.sol";
import {IPool} from "../interfaces/IPool.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
// import {ReentrancyGuardTransient} from "lib/solady/src/utils/ReentrancyGuardTransient.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/solady/src/auth/Ownable.sol";
import {IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "../interfaces/IPoolAddressesProvider.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract Superman is ReentrancyGuard, Ownable, IFlashLoanSimpleReceiver {
    error Superman__UnauthorisedAccess();
    error Superman__InvalidInitiator();
    error Superman__TransferFailed(address token, address owner);

    using SafeTransferLib for address;

    IPool private pool;
    IPoolAddressesProvider private poolAddressesProvider;

    constructor(address _owner, address _pool, address _poolAddressesProvider) {
        _initializeOwner(_owner);
        pool = IPool(_pool);
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
    }

    // Function to check if the user account is liquidatable
    function isLiquidatable(address user)
        external
        view
        returns (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        )
    {
        return pool.getUserAccountData(user);
    }

    function liquidate(
        address collateralAsset,
        address debtAsset,
        address user,
        uint256 debtToCover,
        bool receiveAToken
    ) external nonReentrant {
        // Validate inputs
        require(debtToCover > 0, "Invalid debt amount");
        require(debtToCover <= type(uint256).max / 2, "Debt amount too large"); // Prevent potential overflows

        // Use a very small amount for initial test
        uint256 actualDebtToCover = debtToCover;

        // Get initial balances
        uint256 initialCollateralBalance = collateralAsset.balanceOf(address(this));
        uint256 initialDebtBalance = debtAsset.balanceOf(address(this));

        console.log("Pre-liquidation balances:");
        console.log("Contract collateral:", initialCollateralBalance);
        console.log("Contract debt:", initialDebtBalance);

        if (debtAsset.balanceOf(msg.sender) >= actualDebtToCover) {
            // Transfer and approve with safety checks
            require(debtAsset.balanceOf(msg.sender) >= actualDebtToCover, "Insufficient balance");

            debtAsset.safeTransferFrom(msg.sender, address(this), actualDebtToCover);
            // require(success, "Transfer failed");

            debtAsset.safeApprove(address(pool), 0); // Clear previous approval
            debtAsset.safeApprove(address(pool), actualDebtToCover);

            // Execute liquidation
            pool.liquidationCall(collateralAsset, debtAsset, user, actualDebtToCover, receiveAToken);

            // Transfer assets back with safety checks
            uint256 finalCollateralBalance = collateralAsset.balanceOf(address(this));
            uint256 finalDebtBalance = debtAsset.balanceOf(address(this));

            console.log("Post-liquidation balances:");
            console.log("Contract collateral:", finalCollateralBalance);
            console.log("Contract debt:", finalDebtBalance);

            if (finalCollateralBalance > initialCollateralBalance) {
                collateralAsset.safeTransfer(owner(), finalCollateralBalance - initialCollateralBalance);
            }

            if (finalDebtBalance > initialDebtBalance) {
                debtAsset.safeTransfer(owner(), finalDebtBalance - initialDebtBalance);
            }
        } else {
            revert("Insufficient balance for liquidation");
        }
    }

    function _takeFlashLoan(
        address receiverAddress,
        address asset, // debt asset address
        uint256 amount, // debtToCover
        bytes memory params,
        uint16 referralCode // default to 0 currently
    ) internal nonReentrant {
        pool.flashLoanSimple(receiverAddress, asset, amount, params, referralCode);
    }

    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        // TODO: Put modifiers such as nonReentrant, etc wherever necessary
        if (msg.sender != address(pool)) {
            revert Superman__UnauthorisedAccess();
        }
        if (initiator != address(this)) {
            revert Superman__InvalidInitiator();
        }

        // Estimate gas cost for the entire operation (can be adjusted based on network conditions)
        // uint256 estimatedGasCost = 300000 * tx.gasprice; // Approximate gas units * current gas price (gasLeft() * tx.gasprice)

        // Convert gas cost to token terms (you'll need a price oracle in production)
        // uint256 gasCostInTokens = estimatedGasCost; // This should be converted to token terms using an oracle

        // Calculate total costs (premium + gas)
        // uint256 totalCosts = premium + gasCostInTokens;

        // Calculate minimum profitable amount (including costs and price impact buffer)
        // uint256 minProfitableAmount = amount + (amount * priceImpact / PRECISION);

        asset.safeApprove(address(pool), amount);

        (address collateralAsset, address user) = abi.decode(params, (address, address));
        pool.liquidationCall(collateralAsset, asset, user, amount, false); // Debug what exactly does this do?

        // approve which contract to pull asset of amount + premium
        asset.safeApprove(address(pool), amount + premium);

        uint256 collateralBalance = collateralAsset.balanceOf(address(this));
        collateralAsset.safeTransfer(owner(), collateralBalance); // the collateral that is received as part of the liquidation
        uint256 debtAssetBalance = asset.balanceOf(address(this)) - (amount + premium);
        asset.safeTransfer(owner(), debtAssetBalance); // the execess debt provided to execute liquidation

        return true;
    }

    function ADDRESSES_PROVIDER() external view returns (IPoolAddressesProvider) {
        return poolAddressesProvider;
    }

    function POOL() external view returns (IPool) {
        return pool;
    }

    function withdrawDust() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = owner().call{value: balance}("");
        if (!success) {
            revert Superman__TransferFailed(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, owner()); // For native token
        }
    }

    function withdrawDustTokens(address[] calldata tokens) external nonReentrant onlyOwner {
        uint256 length = tokens.length;
        for (uint256 i = 0; i < length; i++) {
            uint256 balance = IERC20(tokens[i]).balanceOf(address(this));
            address(tokens[i]).safeTransfer(owner(), balance);
        }
    }

    /**
     * @dev Receive function to accept native currency
     */
    receive() external payable {}

    /**
     * @dev Fallback function
     */
    fallback() external payable {}
}
