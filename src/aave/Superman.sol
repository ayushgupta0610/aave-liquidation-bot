// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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
        address collateralAsset, // TODO: What if it's a native token (ETH or something like that)
        address debtAsset,
        address user,
        uint256 debtToCover, // defaulted to uint(-1)
        bool receiveAToken // default: false
    ) external nonReentrant {
        if (debtAsset.balanceOf(address(msg.sender)) >= debtToCover) {
            debtAsset.safeTransferFrom(msg.sender, address(this), debtToCover);
            debtAsset.safeApprove(address(pool), debtToCover);
            pool.liquidationCall(collateralAsset, debtAsset, user, type(uint256).max, receiveAToken); // TODO: Debug what exactly does this do under the hood

            uint256 collateralBalance = collateralAsset.balanceOf(address(this));
            collateralAsset.safeTransfer(owner(), collateralBalance); // the collateral that is received as part of the liquidation
            uint256 debtAssetBalance = debtAsset.balanceOf(address(this));
            debtAsset.safeTransfer(owner(), debtAssetBalance); // the execess debt provided to increase the health factor to 1
        } else {
            // or take a flashloan from pool
            bytes memory params = abi.encode(collateralAsset, user);
            _takeFlashLoan(address(this), debtAsset, debtToCover, params, 0);
            // TODO: Complete the function
        }
    }

    function _takeFlashLoan(
        address receiverAddress,
        address asset, // collateralAsset asset
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

        // TODO: Execute your logic here (params). Take into account the gas fees along with premium
        // Estimate gas cost for the entire operation (can be adjusted based on network conditions)
        // uint256 estimatedGasCost = 300000 * tx.gasprice; // Approximate gas units * current gas price

        // Convert gas cost to token terms (you'll need a price oracle in production)
        // uint256 gasCostInTokens = estimatedGasCost; // This should be converted to token terms using an oracle

        // Calculate total costs (premium + gas)
        // uint256 totalCosts = premium + gasCostInTokens;

        // Calculate minimum profitable amount (including costs and price impact buffer)
        // uint256 minProfitableAmount = amount + (amount * priceImpact / PRECISION);

        asset.safeApprove(address(pool), amount);

        (address collateralAsset, address user) = abi.decode(params, (address, address));
        pool.liquidationCall(collateralAsset, asset, user, type(uint256).max, false); // Debug what exactly does this do?

        // uint256 collateralBalance = collateralAsset.balanceOf(address(this));
        // collateralAsset.safeTransfer(owner(), collateralBalance); // the collateral that is received as part of the liquidation
        // uint256 debtAssetBalance = asset.balanceOf(address(this));
        // asset.safeTransfer(owner(), debtAssetBalance); // the execess debt provided to increase the health factor to 1

        // approve which contract to pull asset of amount + premium
        asset.safeApprove(address(pool), amount + premium);

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
