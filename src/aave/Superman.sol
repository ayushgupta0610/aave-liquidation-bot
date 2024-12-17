// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IPool} from "../interfaces/IPool.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
// import {ReentrancyGuardTransient} from "lib/solady/src/utils/ReentrancyGuardTransient.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/solady/src/auth/Ownable.sol";
import {IFlashLoanSimpleReceiver} from "../interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "../interfaces/IPoolAddressesProvider.sol";
import {IUniswapV2Router02} from "../interfaces/IUniswapV2Router02.sol";
import {IAaveOracle} from "../interfaces/IAaveOracle.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

contract Superman is ReentrancyGuard, Ownable, IFlashLoanSimpleReceiver {
    error Superman__UnauthorisedAccess();
    error Superman__InvalidInitiator();
    error Superman__TransferFailed(address token, address owner);

    using SafeTransferLib for address;

    IPool private pool;
    IPoolAddressesProvider private poolAddressesProvider;
    IUniswapV2Router02 private routerV2;
    IAaveOracle private oracle;

    constructor(address _owner, address _pool, address _poolAddressesProvider, address _routerV2, address _aaveOracle) {
        _initializeOwner(_owner);
        pool = IPool(_pool);
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        routerV2 = IUniswapV2Router02(_routerV2);
        oracle = IAaveOracle(_aaveOracle);
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
        bool receiveAToken,
        uint256 slippageFactor
    ) external nonReentrant {
        // Get user's debt data
        (uint256 totalCollateralBase, uint256 totalDebtBase,,,, uint256 healthFactor) = pool.getUserAccountData(user);

        // TODO: Make this revert messages in require
        require(healthFactor < 1e18, "Position not liquidatable");
        require(slippageFactor < 10000, "Invalida slippage factor");

        // Calculate maximum liquidatable amount (50% of the total debt)
        uint256 maxLiquidatable = totalDebtBase / 2;

        // Use the smaller of debtToCover or maxLiquidatable
        uint256 actualDebtToCover = debtToCover > maxLiquidatable ? maxLiquidatable : debtToCover;

        if (debtAsset.balanceOf(msg.sender) >= actualDebtToCover) {
            // Clear any existing approvals
            debtAsset.safeApprove(address(pool), 0);

            // Get initial balances for tracking
            uint256 initialCollateralBalance = collateralAsset.balanceOf(address(this));
            uint256 initialDebtBalance = debtAsset.balanceOf(address(this));

            // Transfer debt tokens from liquidator
            debtAsset.safeTransferFrom(msg.sender, address(this), actualDebtToCover);

            // Approve and execute liquidation
            debtAsset.safeApprove(address(pool), actualDebtToCover);
            pool.liquidationCall(collateralAsset, debtAsset, user, actualDebtToCover, receiveAToken);

            // Handle received collateral and remaining debt tokens
            uint256 finalCollateralBalance = collateralAsset.balanceOf(address(this));
            uint256 finalDebtBalance = debtAsset.balanceOf(address(this));

            // Transfer received collateral to owner
            if (finalCollateralBalance > initialCollateralBalance) {
                collateralAsset.safeTransfer(owner(), finalCollateralBalance - initialCollateralBalance);
            }

            // Return any unused debt tokens
            if (finalDebtBalance > initialDebtBalance) {
                debtAsset.safeTransfer(owner(), finalDebtBalance - initialDebtBalance);
            }
        } else {
            // If liquidator doesn't have enough debt tokens, use flash loan
            bytes memory params = abi.encode(collateralAsset, user, slippageFactor);
            _takeFlashLoan(address(this), debtAsset, actualDebtToCover, params, 0);
        }
    }

    function _takeFlashLoan(
        address receiverAddress,
        address asset, // debt asset address
        uint256 amount, // debtToCover
        bytes memory params,
        uint16 referralCode // default to 0 currently
    ) internal {
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

        (address collateralAsset, address user, uint256 slippageFactor) =
            abi.decode(params, (address, address, uint256));
        pool.liquidationCall(collateralAsset, asset, user, amount, false);

        // convert collateral token to asset
        uint256 amountIn = collateralAsset.balanceOf(address(this));
        uint256 amountOutMin = calculateAmountOutMin(address(collateralAsset), address(asset), amountIn, slippageFactor);

        address[] memory path = new address[](2);
        path[0] = collateralAsset;
        path[1] = asset;
        collateralAsset.safeApprove(address(routerV2), amountIn);
        routerV2.swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), block.timestamp); // Fix the swap on base

        // approve which contract to pull asset of amount + premium
        asset.safeApprove(address(pool), amount + premium);

        uint256 debtAssetBalance = asset.balanceOf(address(this)) - (amount + premium);
        asset.safeTransfer(owner(), debtAssetBalance); // the execess debt provided to execute liquidation

        return true;
    }

    // Get the weighted price from AaveV3 Oracle
    function calculateAmountOutMin(address collateralAsset, address asset, uint256 amountIn, uint256 slippageFactor)
        internal
        view
        returns (uint256)
    {
        // Get prices in USD (scaled to 8 decimals in Aave Oracle)
        uint256 collateralPriceUsd = oracle.getAssetPrice(collateralAsset);
        uint256 assetPriceUsd = oracle.getAssetPrice(asset);

        // Get decimals for both tokens
        uint256 collateralDecimals = IERC20Metadata(collateralAsset).decimals();
        uint256 assetDecimals = IERC20Metadata(asset).decimals();

        // Calculate theoretical output amount
        // First convert to USD with 8 decimals (Aave oracle precision)
        uint256 amountInUsd = (amountIn * collateralPriceUsd) / (10 ** collateralDecimals);

        // Convert USD amount to asset amount
        uint256 theoreticalOutput = (amountInUsd * (10 ** assetDecimals)) / assetPriceUsd;

        uint256 SLIPPAGE_TOLERANCE = 10000 - slippageFactor; // .5% slippage => slippageFactor = 50
        uint256 amountOutMin = (theoreticalOutput * SLIPPAGE_TOLERANCE) / 10000;

        return amountOutMin;
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
