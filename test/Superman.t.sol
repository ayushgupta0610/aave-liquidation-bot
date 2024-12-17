// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {Superman} from "../src/aave/Superman.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";
import {IPoolAddressesProvider} from "../src/interfaces/IPoolAddressesProvider.sol";
import {IAaveOracle} from "../src/interfaces/IAaveOracle.sol";
import {MockAaveOracle} from "./mocks/MockAaveOracle.sol";
import {MockPoolAddressesProvider} from "./mocks/MockPoolAddressesProvider.sol";
import {MockV3Aggregator} from "./mocks/MockV3Aggregator.sol";

contract SupermanTest is Test {
    using SafeTransferLib for address;

    Superman private superman;
    HelperConfig.NetworkConfig private networkConfig;
    IPool private pool;
    IERC20 collateralToken; // weth
    IERC20 debtToken; // usdc
    address private owner;
    address private liquidator;

    address private immutable user = makeAddr("user");
    uint256 public constant INITIAL_USDC_BALANCE = 1_000_000e6; // 1000_000 USDC
    uint256 public constant INITIAL_WETH_BALANCE = 30 ether; // 30 ethers

    IPoolAddressesProvider private poolAddressesProvider;
    MockAaveOracle private mockAaveOracle;

    // Add constants for testing
    uint256 private constant FLASH_LOAN_PREMIUM = 5; // 0.05%
    uint256 private constant PRECISION = 10000;
    uint8 private constant ORACLE_DECIMAL = 8;
    uint256 private constant SLIPPAGE_FACTOR = 100; // 2.5% (250) slippage required to convert the collateral asset from debt asset (on Base UV2 from WETH to USDC!)

    function setUp() public {
        // Setup contracts
        string memory rpcUrl = vm.envString("ETH_RPC_URL");
        vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        networkConfig = config.getConfig();

        collateralToken = IERC20(networkConfig.weth);
        debtToken = IERC20(networkConfig.usdc);
        mockAaveOracle = new MockAaveOracle();
        owner = networkConfig.account;
        liquidator = owner;

        // Deploy Superman with correct parameters
        poolAddressesProvider = IPoolAddressesProvider(networkConfig.poolAddressesProvider);
        pool = IPool(networkConfig.aavePool);
        superman = new Superman(
            owner, address(pool), address(poolAddressesProvider), networkConfig.routerV2, networkConfig.aaveOracle
        );

        // Additional setup
        deal(networkConfig.weth, address(user), INITIAL_WETH_BALANCE, false);
    }

    function _setupForLiquidation() private {
        uint256 supplyWethAmount = 10 ether;
        uint256 borrowDebtAmount = 30_000 * 1e6;

        // Fund pool with more USDC
        deal(address(debtToken), address(pool), borrowDebtAmount * 10);

        // Set initial prices
        mockAaveOracle.setAssetPrice(address(collateralToken), 4000e8); // WETH at $4000
        mockAaveOracle.setAssetPrice(address(debtToken), 1e8); // USDC at $1

        // Mock oracle
        vm.mockCall(
            address(poolAddressesProvider),
            abi.encodeWithSelector(IPoolAddressesProvider.getPriceOracle.selector),
            abi.encode(address(mockAaveOracle))
        );

        vm.startPrank(user);
        address(collateralToken).safeApprove(address(pool), supplyWethAmount);
        pool.supply(address(collateralToken), supplyWethAmount, user, 0);
        pool.borrow(address(debtToken), borrowDebtAmount, 2, 0, user);
        vm.stopPrank();

        // Crash price by 75% to ensure liquidation
        mockAaveOracle.setAssetPrice(address(collateralToken), 1000e8); // Drop to $1000

        // Verify liquidatable state
        (,,,,, uint256 healthFactor) = pool.getUserAccountData(user);
        require(healthFactor < 1e18, "Position not liquidatable");
    }

    function testLiquidationHavingDebtToCover() public {
        _setupForLiquidation();

        // Store initial balances
        uint256 initialOwnerCollateral = collateralToken.balanceOf(liquidator);
        uint256 initialOwnerDebt = debtToken.balanceOf(liquidator);
        uint256 initialUserCollateral = collateralToken.balanceOf(user);

        // Get total debt
        (, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);

        // Try to liquidate 75% of the debt (should be capped at 50%)
        uint256 debtToCover = (totalDebtBase * 75) / 100;

        // Fund liquidator
        deal(address(debtToken), liquidator, debtToCover);

        vm.startPrank(liquidator);
        debtToken.approve(address(superman), debtToCover);

        superman.liquidate(address(collateralToken), address(debtToken), user, debtToCover, false, SLIPPAGE_FACTOR);
        vm.stopPrank();

        // Verify results
        (uint256 finalTotalCollateralBase, uint256 finalTotalDebtBase,,,,) = pool.getUserAccountData(user);

        // Check that no more than 50% was liquidated
        assertGe(finalTotalDebtBase, totalDebtBase / 2, "Cannot liquidate more than 50%");
        assertLt(finalTotalDebtBase, totalDebtBase, "Should have liquidated some debt");

        // Check collateral transfer
        assertGt(collateralToken.balanceOf(liquidator), initialOwnerCollateral, "Owner should receive collateral");

        // Verify Superman contract has no leftover tokens
        assertEq(collateralToken.balanceOf(address(superman)), 0, "Superman should not have collateral tokens");
        assertEq(debtToken.balanceOf(address(superman)), 0, "Superman should not have debt tokens");
    }

    function testLiquidationWithoutDebtToCover() public {
        _setupForLiquidation();

        // Store initial balances
        // uint256 initialOwnerCollateral = collateralToken.balanceOf(liquidator);

        // Get total debt
        (, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);

        // Try to liquidate 75% of the debt (should be capped at 50%)
        uint256 debtToCover = (totalDebtBase * 75) / 100;

        // Fund liquidator (This won't be there)
        // deal(address(debtToken), liquidator, debtToCover);

        vm.startPrank(liquidator);
        debtToken.approve(address(superman), debtToCover);

        superman.liquidate(address(collateralToken), address(debtToken), user, debtToCover, false, SLIPPAGE_FACTOR);
        vm.stopPrank();

        // Verify results
        (uint256 finalTotalCollateralBase, uint256 finalTotalDebtBase,,,,) = pool.getUserAccountData(user);

        // Check that no more than 50% was liquidated
        assertGe(finalTotalDebtBase, totalDebtBase / 2, "Cannot liquidate more than 50%");
        assertLt(finalTotalDebtBase, totalDebtBase, "Should have liquidated some debt");

        // Verify Superman contract has no leftover tokens
        assertEq(collateralToken.balanceOf(address(superman)), 0, "Superman should not have collateral tokens");
        assertEq(debtToken.balanceOf(address(superman)), 0, "Superman should not have debt tokens");
    }
}
