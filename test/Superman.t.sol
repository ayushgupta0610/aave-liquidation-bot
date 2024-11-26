// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {Superman} from "../src/aave/Superman.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IPoolAddressesProvider} from "../src/interfaces/IPoolAddressesProvider.sol";
import {IAaveOracle} from "../src/interfaces/IAaveOracle.sol";

contract SupermanTest is Test {
    using SafeTransferLib for address;

    Superman private superman;
    HelperConfig.NetworkConfig private networkConfig;
    IPool private pool;
    IERC20 collateralToken;
    IERC20 debtToken;
    address private user;
    address private liquidator;
    address private owner;

    uint256 public constant INITIAL_BALANCE = 1_000_000e6; // 1000_000 USDC

    IPoolAddressesProvider private poolAddressesProvider;

    // Add constants for testing
    uint256 private constant FLASH_LOAN_PREMIUM = 5; // 0.05%
    uint256 private constant PRICE_IMPACT = 100; // 1%
    uint256 private constant PRECISION = 10000;

    function setUp() public {
        // Deploy mocks
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        networkConfig = config.getConfig();

        pool = IPool(networkConfig.aavePool);
        collateralToken = IERC20(networkConfig.usdc);
        debtToken = IERC20(networkConfig.weth);
        owner = networkConfig.account;

        poolAddressesProvider = IPoolAddressesProvider(networkConfig.poolAddressesProvider);

        // Deploy Superman with correct parameters
        superman = new Superman(owner, address(pool), address(poolAddressesProvider));

        // Additional setup
        vm.deal(address(superman), 1 ether); // Add some ETH for testing
        deal(address(collateralToken), address(superman), INITIAL_BALANCE);
        deal(address(debtToken), address(superman), INITIAL_BALANCE);

        // Setup test accounts
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");

        // Fund liquidator
        vm.prank(liquidator);
        collateralToken.approve(address(superman), type(uint256).max);
    }

    function testLiquidate() public {
        uint256 debtAmount = 100e18;
        uint256 collateralBonus = 110e18; // Assuming 10% bonus

        // Setup tokens
        // collateralToken.mint(address(pool), collateralBonus);
        // pool.setTokens(address(collateralToken), address(debtToken));

        // Perform liquidation
        vm.prank(liquidator);
        superman.liquidate(address(collateralToken), address(debtToken), address(this), debtAmount, false);

        // Verify liquidator received collateral
        assertEq(collateralToken.balanceOf(liquidator), collateralBonus);
        // Verify Superman contract has no remaining balance
        assertEq(collateralToken.balanceOf(address(superman)), 0);
        assertEq(debtToken.balanceOf(address(superman)), 0);
    }

    function testLiquidateRevertsOnInsufficientApproval() public {
        uint256 debtAmount = 100e18;

        // Remove approval
        vm.prank(liquidator);
        debtToken.approve(address(superman), 0);

        // Expect revert on liquidation
        vm.prank(liquidator);
        vm.expectRevert();
        superman.liquidate(address(collateralToken), address(debtToken), address(this), debtAmount, false);
    }

    // Add new tests
    function testIsLiquidatable() public {
        // Setup a user with unhealthy position
        _setupUnhealthyPosition();

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = superman.isLiquidatable(address(this));

        assertTrue(healthFactor < 1e18, "Position should be liquidatable");
        assertGt(totalCollateralBase, 0, "Should have collateral");
        assertGt(totalDebtBase, 0, "Should have debt");
    }

    function testLiquidateWithSufficientBalance() public {
        // Setup
        _setupUnhealthyPosition();
        uint256 debtAmount = 100e18;

        vm.startPrank(liquidator);
        deal(address(debtToken), liquidator, debtAmount);
        debtToken.approve(address(superman), debtAmount);

        // Pre-state checks
        uint256 liquidatorBalanceBefore = collateralToken.balanceOf(liquidator);

        // Execute
        superman.liquidate(address(collateralToken), address(debtToken), address(this), debtAmount, false);

        // Post-state checks
        uint256 liquidatorBalanceAfter = collateralToken.balanceOf(liquidator);
        assertGt(liquidatorBalanceAfter, liquidatorBalanceBefore, "Liquidator should receive collateral");
        vm.stopPrank();
    }

    function testLiquidateWithFlashLoan() public {
        // Setup
        _setupUnhealthyPosition();
        uint256 debtAmount = 1000e18; // Large amount requiring flash loan

        vm.startPrank(liquidator);
        superman.liquidate(address(collateralToken), address(debtToken), address(this), debtAmount, false);

        // Verify flash loan was successful
        assertEq(debtToken.balanceOf(address(superman)), 0, "Should have no remaining debt token");
        assertGt(collateralToken.balanceOf(liquidator), 0, "Should have received collateral");
        vm.stopPrank();
    }

    function testWithdrawDust() public {
        // Setup
        uint256 ethAmount = 1 ether;
        uint256 balanceBefore = owner.balance;
        vm.deal(address(superman), ethAmount);

        // Execute
        vm.prank(owner);
        superman.withdrawDust();

        // Verify
        assertEq(address(superman).balance, 0);
        assertEq(owner.balance - balanceBefore, ethAmount);
    }

    function testWithdrawDustTokens() public {
        // Setup
        address[] memory tokens = new address[](2);
        tokens[0] = address(collateralToken);
        tokens[1] = address(debtToken);

        deal(address(collateralToken), address(superman), 100e18);
        deal(address(debtToken), address(superman), 100e18);

        // Execute
        vm.prank(owner);
        superman.withdrawDustTokens(tokens);

        // Verify
        assertEq(collateralToken.balanceOf(address(superman)), 0);
        assertEq(debtToken.balanceOf(address(superman)), 0);
    }

    // Helper functions (TODO)
    function _setupUnhealthyPosition() internal {
        // Deposit $100 worth of collateral and take a loan of $75, then take another loan of $5
        // Supply initial WETH as collateral
        uint256 collateralAmount = 4000 * 1e6;
        address(collateralToken).safeApprove(address(this), collateralAmount);
        pool.supply(address(collateralToken), collateralAmount, address(this), 0);

        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(address(this));
        console.log("totalCollateralBase: ", totalCollateralBase);
        console.log("totalDebtBase: ", totalDebtBase);
        console.log("availableBorrowsBase: ", availableBorrowsBase);
        console.log("currentLiquidationThreshold: ", currentLiquidationThreshold);
        console.log("ltv: ", ltv);
        console.log("healthFactor: ", healthFactor);

        // uint256 borrowAmount = 85% of the collateral amount
        // pool.borrow(debtToken, borrowAmount, 2, 0, address(this));
    }

    // Fuzz tests
    function testFuzz_Liquidate(uint256 debtAmount) public {
        vm.assume(debtAmount > 0 && debtAmount < 1_000_000e18);
        _setupUnhealthyPosition();

        vm.startPrank(liquidator);
        deal(address(debtToken), liquidator, debtAmount);
        debtToken.approve(address(superman), debtAmount);

        superman.liquidate(address(collateralToken), address(debtToken), address(this), debtAmount, false);
        vm.stopPrank();
    }

    function testSetupUnhealthyPosition() public {
        // Supply initial WETH as collateral
        uint256 collateralAmount = 4000 * 1e6;
        deal(address(collateralToken), address(user), collateralAmount);
        vm.startPrank(user);
        address(collateralToken).safeApprove(address(pool), collateralAmount);
        pool.supply(address(collateralToken), collateralAmount, user, 0);
        (
            uint256 totalCollateralBase,
            uint256 totalDebtBase,
            uint256 availableBorrowsBase,
            uint256 currentLiquidationThreshold,
            uint256 ltv,
            uint256 healthFactor
        ) = pool.getUserAccountData(address(user));
        uint256 maxBorrowAmountInUsd = ltv * totalCollateralBase / (1e8 * 1e4);
        console.log("maxBorrowAmountInUsd: ", maxBorrowAmountInUsd);
        address oracleAddress = poolAddressesProvider.getPriceOracle();
        uint256 ethPrice = IAaveOracle(oracleAddress).getAssetPrice(address(debtToken));
        console.log("ethPrice: ", ethPrice);
        uint256 borrowAmount = maxBorrowAmountInUsd * 1e8 * 1e18 / ethPrice;
        console.log("borrowAmount: ", borrowAmount);
        pool.borrow(address(debtToken), borrowAmount, 2, 0, address(user));
        (totalCollateralBase, totalDebtBase, availableBorrowsBase, currentLiquidationThreshold, ltv, healthFactor) =
            pool.getUserAccountData(address(user));
        console.log("totalCollateralBase: ", totalCollateralBase);
        console.log("totalDebtBase: ", totalDebtBase);
        console.log("availableBorrowsBase: ", availableBorrowsBase);
        console.log("currentLiquidationThreshold: ", currentLiquidationThreshold);
        console.log("ltv: ", ltv);
        console.log("healthFactor: ", healthFactor);
    }
}
