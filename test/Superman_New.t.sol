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
    address private user;
    address private liquidator;
    address private owner;

    uint256 public constant INITIAL_USDC_BALANCE = 1_000_000e6; // 1000_000 USDC
    uint256 public constant INITIAL_WETH_BALANCE = 100 ether; // 100 ethers

    IPoolAddressesProvider private poolAddressesProvider;
    MockAaveOracle private mockAaveOracle;
    IAaveOracle private aaveOracle;

    // Add constants for testing
    uint256 private constant FLASH_LOAN_PREMIUM = 5; // 0.05%
    uint256 private constant PRECISION = 10000;
    uint8 private constant ORACLE_DECIMAL = 8;

    function setUp() public {
        // Setup test accounts
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");

        // Deploy mocks
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        networkConfig = config.getConfig();

        collateralToken = IERC20(networkConfig.weth);
        debtToken = IERC20(networkConfig.usdc);
        owner = networkConfig.account;

        // Deploy Superman with correct parameters
        poolAddressesProvider = IPoolAddressesProvider(networkConfig.poolAddressesProvider);
        address oracleAddress = poolAddressesProvider.getPriceOracle();
        aaveOracle = IAaveOracle(oracleAddress);
        pool = IPool(networkConfig.aavePool);
        superman = new Superman(owner, address(pool), address(poolAddressesProvider));

        // Additional setup
        // vm.deal(address(superman), 1 ether); // Add some ETH for testing
        deal(networkConfig.weth, address(user), INITIAL_WETH_BALANCE, false);
        console.log("Collateral token balance: ", collateralToken.balanceOf(user));
        deal(networkConfig.usdc, address(liquidator), INITIAL_USDC_BALANCE, true);
        // deal(networkConfig.usdc, address(user), INITIAL_USDC_BALANCE, true);

        // Fund liquidator
        // vm.prank(liquidator);
        // debtToken.approve(address(pool), type(uint256).max);
    }

    function testLiquidation() public {
        uint256 supplyWethAmount = 10 ether; // Around $40k
        uint256 borrowDebtAmount = 25_000 * 1e6; // Precisely $!5k
        // Supply collateral
        vm.startPrank(user);

        address(collateralToken).safeApprove(address(pool), supplyWethAmount);
        pool.supply(address(collateralToken), supplyWethAmount, user, 0);

        // Borrow USDC
        pool.borrow(address(debtToken), borrowDebtAmount, 2, 0, user);
        vm.stopPrank();

        // Method 1: Decrease WETH price by 50% to trigger liquidation
        int256 mockWethPrice = int256(4000) * int256(10 ** ORACLE_DECIMAL);
        MockV3Aggregator mockWethPriceFeed = new MockV3Aggregator(ORACLE_DECIMAL, mockWethPrice);

        // Set new price (50% lower)
        int256 newPrice = (mockWethPriceFeed.latestAnswer() * 50) / 100;
        mockWethPriceFeed.updateAnswer(newPrice);

        // Replace price feed in Aave's oracle
        vm.mockCall(
            address(poolAddressesProvider),
            abi.encodeWithSelector(IPoolAddressesProvider.getPriceOracle.selector),
            abi.encode(address(mockWethPriceFeed))
        );

        // Verify user can be liquidated
        (
            , // collateral
            , // debt
            , // availableBorrowsBase
            , // currentLiquidationThreshold
            uint256 ltv, // ltv
            uint256 healthFactor
        ) = pool.getUserAccountData(user);
        // console.log("totalCollateralBase: ", collateral);
        // console.log("totalDebtBase: ", debt);
        // console.log("availableBorrowsBase: ", availableBorrowsBase);
        // console.log("currentLiquidationThreshold: ", currentLiquidationThreshold);
        console.log("ltv: ", ltv);
        console.log("healthFactor: ", healthFactor);

        // assertTrue(healthFactorBelowThreshold, "User should be liquidatable");

        // Perform liquidation
        vm.startPrank(liquidator);
        // Calculate the debt to cover if possible
        uint256 debtToCover = 5_000 * 1e6;
        debtToken.approve(address(pool), debtToCover);
        pool.liquidationCall(
            address(collateralToken), // collateral
            address(debtToken), // debt
            user, // user to liquidate
            debtToCover, // debt to cover
            false // receive aToken
        );
        vm.stopPrank();
    }
}
