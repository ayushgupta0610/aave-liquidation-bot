// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {TakeFlashLoan} from "../src/TakeFlashLoan.sol";
import {IPool} from "../src/interfaces/IPool.sol";
import {HelperConfig} from "../script/HelperConfig.s.sol";

contract FlashLoanTest is Test {
    using SafeTransferLib for address;

    TakeFlashLoan private flashLoan;
    HelperConfig.NetworkConfig private networkConfig;
    IPool private pool;
    IERC20 collateralToken;
    IERC20 debtToken;
    address private user;

    uint256 public constant INITIAL_BALANCE = 100_000e6; // 1000_000 USDC

    address private constant USDC = 0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913;
    address private constant WETH = 0x4200000000000000000000000000000000000006;
    uint256 private constant FLASH_LOAN_AMOUNT = 1000e6; // 1000 USDC
    uint256 private constant FLASH_LOAN_PREMIUM = 5; // 0.05% premium

    function setUp() public {
        // Deploy mocks
        string memory rpcUrl = vm.envString("BASE_RPC_URL");
        vm.createSelectFork(rpcUrl);

        HelperConfig config = new HelperConfig();
        networkConfig = config.getConfig();

        // pool = IPool(networkConfig.aavePool);
        // collateralToken = IERC20(networkConfig.usdc);
        // debtToken = IERC20(networkConfig.weth);

        // Deploy FlashLoan
        address owner = 0x47D1111fEC887a7BEb7839bBf0E1b3d215669D86;
        address poolAddress = 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5; // pool address on Base
        address poolAddressesProvider = 0xe20fCBdBfFC4Dd138cE8b2E6FBb6CB49777ad64D; // pool address provider on Base
        address uniswapV2Factory = 0x8909Dc15e40173Ff4699343b6eB8132c65e18eC6;
        flashLoan = new TakeFlashLoan(owner, poolAddress, poolAddressesProvider, uniswapV2Factory);

        // Setup test accounts
        user = makeAddr("user");
    }

    function testFlashLoan() public {}

    function testSetup() public view {
        assertEq(flashLoan.owner(), 0x47D1111fEC887a7BEb7839bBf0E1b3d215669D86);
        assertEq(address(flashLoan.POOL()), 0xA238Dd80C259a72e81d7e4664a9801593F98d1c5);
    }

    function testTakeFlashLoan() public {
        uint256 amountOutMin = 0; // In production, this should be calculated based on price impact
        uint256 amountOut = FLASH_LOAN_AMOUNT + (FLASH_LOAN_AMOUNT * FLASH_LOAN_PREMIUM / 10000);

        // Fund the contract with enough USDC to cover the premium
        deal(USDC, address(flashLoan), FLASH_LOAN_AMOUNT * FLASH_LOAN_PREMIUM / 10000, true);

        vm.prank(user);
        flashLoan.takeFlashLoan(USDC, FLASH_LOAN_AMOUNT, WETH, amountOutMin, amountOut);

        uint256 allowance = IERC20(USDC).allowance(address(flashLoan), user);
        assertEq(allowance, 0);
    }

    function testCalculatePriceImpact() public view {
        uint256 priceImpact = flashLoan.calculatePriceImpact(USDC, FLASH_LOAN_AMOUNT, WETH);
        // Price impact should be reasonable (less than 1%)
        assertLt(priceImpact, 100); // 100 = 1%
    }

    function testWithdrawDust() public {
        // Fund contract with some ETH
        vm.deal(address(flashLoan), 1 ether);

        uint256 ownerBalanceBefore = flashLoan.owner().balance;

        vm.prank(flashLoan.owner());
        flashLoan.withdrawDust();

        assertEq(address(flashLoan).balance, 0);
        assertEq(flashLoan.owner().balance, ownerBalanceBefore + 1 ether);
    }

    function testWithdrawDustTokens() public {
        address[] memory tokens = new address[](2);
        tokens[0] = USDC;
        tokens[1] = WETH;

        // Fund contract with tokens
        deal(USDC, address(flashLoan), 1000e6);
        deal(WETH, address(flashLoan), 1 ether);

        uint256 ownerUsdcBefore = IERC20(USDC).balanceOf(flashLoan.owner());
        uint256 ownerWethBefore = IERC20(WETH).balanceOf(flashLoan.owner());

        vm.prank(flashLoan.owner());
        flashLoan.withdrawDustTokens(tokens);

        assertEq(IERC20(USDC).balanceOf(address(flashLoan)), 0);
        assertEq(IERC20(WETH).balanceOf(address(flashLoan)), 0);
        assertEq(IERC20(USDC).balanceOf(flashLoan.owner()), ownerUsdcBefore + 1000e6);
        assertEq(IERC20(WETH).balanceOf(flashLoan.owner()), ownerWethBefore + 1 ether);
    }

    function testRevertOnUnauthorizedWithdrawDust() public {
        vm.deal(address(flashLoan), 1 ether);

        vm.expectRevert();
        flashLoan.withdrawDust();
    }

    function testRevertOnUnauthorizedWithdrawDustTokens() public {
        address[] memory tokens = new address[](1);
        tokens[0] = USDC;

        deal(USDC, address(flashLoan), 1000e6);

        vm.prank(address(0xBEEF));
        vm.expectRevert();
        flashLoan.withdrawDustTokens(tokens);
    }

    function testExecuteOperationUnauthorizedAccess() public {
        vm.expectRevert(TakeFlashLoan.FlashLoan__UnauthorisedAccess.selector);
        flashLoan.executeOperation(USDC, FLASH_LOAN_AMOUNT, FLASH_LOAN_PREMIUM, address(flashLoan), "");
    }

    function testExecuteOperationInvalidInitiator() public {
        vm.prank(address(flashLoan.POOL()));
        vm.expectRevert(TakeFlashLoan.FlashLoan__InvalidInitiator.selector);
        flashLoan.executeOperation(USDC, FLASH_LOAN_AMOUNT, FLASH_LOAN_PREMIUM, address(0xBEEF), "");
    }

    // Helper function to receive ETH
    receive() external payable {}
}
