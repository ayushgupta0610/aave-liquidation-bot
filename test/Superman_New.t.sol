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

    function setUp() public {
        // Setup contracts
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
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
        superman = new Superman(owner, address(pool), address(poolAddressesProvider));

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
        console.log("Health Factor after price crash:", healthFactor);
        require(healthFactor < 1e18, "Position not liquidatable");
    }

    function testLiquidationHavingDebtToCover() public {
        _setupForLiquidation();

        // Store initial balances
        uint256 initialOwnerCollateral = collateralToken.balanceOf(liquidator);
        uint256 initialOwnerDebt = debtToken.balanceOf(liquidator);
        uint256 initialUserCollateral = collateralToken.balanceOf(user);

        console.log("Initial balances:");
        console.log("Owner collateral:", initialOwnerCollateral);
        console.log("Owner debt:", initialOwnerDebt);
        console.log("User collateral:", initialUserCollateral);

        // Calculate a very small debtToCover (0.1% of total debt)
        (, uint256 totalDebtBase,,,,) = pool.getUserAccountData(user);
        uint256 debtToCover = 1 * 1e6; // Just 100 USDC to start
        console.log("Debt to cover:", debtToCover);
        console.log("totalDebtBase:", totalDebtBase);

        // Give liquidator enough USDC
        deal(address(debtToken), liquidator, debtToCover * 2);
        console.log("Liquidator USDC balance:", debtToken.balanceOf(liquidator));

        vm.startPrank(liquidator);

        // Log pre-liquidation approvals
        console.log("Pre-liquidation approval:", debtToken.allowance(liquidator, address(superman)));

        // Approve Superman to use USDC
        debtToken.approve(address(superman), debtToCover);
        console.log("Post-approval amount:", debtToken.allowance(liquidator, address(superman)));

        console.log("=== Starting liquidation ===");

        try superman.liquidate(address(collateralToken), address(debtToken), user, debtToCover, false) {
            console.log("Liquidation succeeded");
        } catch Error(string memory reason) {
            console.log("Liquidation failed with reason:", reason);
        } catch (bytes memory) {
            console.log("Liquidation failed with low-level error");
        }

        vm.stopPrank();

        // Log final balances
        console.log("Final balances:");
        console.log("liquidator collateral:", collateralToken.balanceOf(liquidator));
        console.log("liquidator debt:", debtToken.balanceOf(liquidator));
        console.log("User collateral:", collateralToken.balanceOf(user));
    }

    function testLiquidationWithoutDebtToCover() public {
        _setupForLiquidation();
        // Perform liquidation
        uint256 debtToCover = 5_000 * 1e6;
        liquidator = owner; // Making the liquidator the owner here so that all the assets are transferred back to the owner
        vm.startPrank(liquidator);
        // TODO: Calculate the debt to cover (since max 50% can be liquidated)
        debtToken.approve(address(superman), debtToCover);
        superman.liquidate(
            address(collateralToken),
            address(debtToken),
            user,
            debtToCover, // defaulted to uint(-1)
            false // default: false
        );

        vm.stopPrank();
    }
}
