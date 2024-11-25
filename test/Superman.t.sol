// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {Superman} from "../src/aave/Superman.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract SupermanTest is Test {
    using SafeTransferLib for address;

    Superman private superman;
    HelperConfig.NetworkConfig private networkConfig;
    IPool private pool;
    IERC20 collateralToken;
    IERC20 debtToken;
    address private user;
    address private liquidator;

    uint256 public constant INITIAL_BALANCE = 100_000e6; // 1000_000 USDC

    function setUp() public {
        // Deploy mocks
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        networkConfig = config.getConfig();

        pool = IPool(networkConfig.aavePool);
        collateralToken = IERC20(networkConfig.usdc);
        debtToken = IERC20(networkConfig.weth);

        // Deploy Superman
        superman = new Superman(address(pool));

        // Setup test accounts
        user = makeAddr("user");
        liquidator = makeAddr("liquidator");

        // Fund liquidator
        vm.prank(liquidator);
        collateralToken.approve(address(superman), type(uint256).max);
    }

    // function testIsLiquidatable() public view {
    //     // Setup mock return values
    //     uint256 totalCollateralBase = 100e18;
    //     uint256 totalDebtBase = 90e18;
    //     uint256 availableBorrowsBase = 10e18;
    //     uint256 currentLiquidationThreshold = 85_00; // 85%
    //     uint256 ltv = 80_00; // 80%
    //     uint256 healthFactor = 0.9e18; // < 1, means liquidatable

    //     (
    //         uint256 retCollateral,
    //         uint256 retDebt,
    //         uint256 retBorrows,
    //         uint256 retThreshold,
    //         uint256 retLtv,
    //         uint256 retHealth
    //     ) = superman.isLiquidatable(user);

    //     assertEq(retCollateral, totalCollateralBase);
    //     assertEq(retDebt, totalDebtBase);
    //     assertEq(retBorrows, availableBorrowsBase);
    //     assertEq(retThreshold, currentLiquidationThreshold);
    //     assertEq(retLtv, ltv);
    //     assertEq(retHealth, healthFactor);
    // }

    function testLiquidate() public {
        uint256 debtAmount = 100e18;
        uint256 collateralBonus = 110e18; // Assuming 10% bonus

        // Setup tokens
        // collateralToken.mint(address(pool), collateralBonus);
        // pool.setTokens(address(collateralToken), address(debtToken));

        // Perform liquidation
        vm.prank(liquidator);
        superman.liquidate(address(collateralToken), address(debtToken), user, debtAmount, false);

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
        superman.liquidate(address(collateralToken), address(debtToken), user, debtAmount, false);
    }
}
