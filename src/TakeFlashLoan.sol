// SPDX-License-Identifer: MIT
pragma solidity ^0.8.28;

// import {console2} from "forge-std/console2.sol";
import {ReentrancyGuard} from "lib/solady/src/utils/ReentrancyGuard.sol";
import {Ownable} from "lib/solady/src/auth/Ownable.sol";
import {IPool} from "./interfaces/IPool.sol";
import {IUniswapV2Pair} from "./interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router02} from "./interfaces/IUniswapV2Router02.sol";
import {IUniswapV2Factory} from "./interfaces/IUniswapV2Factory.sol";
import {IFlashLoanSimpleReceiver} from "./interfaces/IFlashLoanSimpleReceiver.sol";
import {IPoolAddressesProvider} from "./interfaces/IPoolAddressesProvider.sol";
import {SafeTransferLib} from "lib/solady/src/utils/SafeTransferLib.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";

contract TakeFlashLoan is ReentrancyGuard, Ownable, IFlashLoanSimpleReceiver {
    error FlashLoan__UnauthorisedAccess();
    error FlashLoan__InvalidInitiator();
    error FlashLoan__TransferFailed(address token, address owner);

    using SafeTransferLib for address;

    IPool private pool;
    IPoolAddressesProvider private poolAddressesProvider;
    IUniswapV2Router02 private routerV2;
    IUniswapV2Factory private factory;

    // Constant for precision in percentage calculations (100% = 10000)
    uint256 private constant PRECISION = 10000;

    // TODO: Emit events

    constructor(address _owner, address _pool, address _poolAddressesProvider, address _uniswapV2Factory) {
        _initializeOwner(_owner);
        pool = IPool(_pool);
        poolAddressesProvider = IPoolAddressesProvider(_poolAddressesProvider);
        factory = IUniswapV2Factory(_uniswapV2Factory);
    }

    function takeFlashLoan(address tokenIn, uint256 amountIn, address tokenOut, uint256 amountOutMin, uint256 amountOut)
        external
    {
        bytes memory params = abi.encode(tokenOut, amountOutMin, amountOut);
        pool.flashLoanSimple(
            address(this), // receiver
            tokenIn, // asset to take flash loan of
            amountIn, // amount of asset to take flash loan of
            params, // payload to encode data to be decoded by the flashLoanReceiver
            0 // uint16 referralCode
        );
    }

    /**
     * @notice Executes an operation after receiving the flash-borrowed asset
     * @dev Ensure that the contract can return the debt + premium, e.g., has
     *      enough funds to repay and has approved the Pool to pull the total amount
     * @param asset The address of the flash-borrowed asset
     * @param amount The amount of the flash-borrowed asset
     * @param premium The fee of the flash-borrowed asset
     * @param initiator The address of the flashloan initiator
     * @param params The byte-encoded params passed when initiating the flashloan
     * @return True if the execution of the operation succeeds, false otherwise
     */
    function executeOperation(address asset, uint256 amount, uint256 premium, address initiator, bytes calldata params)
        external
        returns (bool)
    {
        // TODO: Put modifiers such as nonReentrant, etc wherever necessary
        if (msg.sender != address(pool)) {
            revert FlashLoan__UnauthorisedAccess();
        }
        if (initiator != address(this)) {
            revert FlashLoan__InvalidInitiator();
        }

        // console2.log("Balance of asset before: ", asset.balanceOf(address(this)));
        // (address tokenOut, uint256 amountOutMin, uint256 amountOut) = abi.decode(params, (address, uint256, uint256));

        // if after price impact the swap is profitable, execute the swap. TODO: Take into account the gas fees along with premium
        // uint256 priceImpact = calculatePriceImpact(asset, amount, tokenOut);

        // Estimate gas cost for the entire operation (can be adjusted based on network conditions)
        // uint256 estimatedGasCost = 300000 * tx.gasprice; // Approximate gas units * current gas price

        // Convert gas cost to token terms (you'll need a price oracle in production)
        // uint256 gasCostInTokens = estimatedGasCost; // This should be converted to token terms using an oracle

        // Calculate total costs (premium + gas)
        // uint256 totalCosts = premium + gasCostInTokens;

        // Calculate minimum profitable amount (including costs and price impact buffer)
        // uint256 minProfitableAmount = amount + (amount * priceImpact / PRECISION);

        // Only execute swap if expected output is greater than minimum profitable amount
        // if (amountOut > minProfitableAmount) {
        //     address[] memory path = new address[](2);
        //     path[0] = asset;
        //     path[1] = tokenOut;
        //     executeSwap(amount, amountOutMin, path, address(this), block.timestamp + 24 hours);
        // } else {
        //     revert("Swap not profitable after costs");
        // }

        // ensure the contract has enough funds post execution of params calldata
        // console2.log("Balance of asset after: ", asset.balanceOf(address(this)));

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

    /**
     * @dev Calculates the price impact of a swap
     * @param tokenIn Address of input token
     * @param amountIn Amount of input tokens
     * @param tokenOut Address of output token
     * @return priceImpact Price impact as a percentage with 2 decimal places (e.g., 1234 = 12.34%)
     */
    function calculatePriceImpact(address tokenIn, uint256 amountIn, address tokenOut)
        public
        view
        returns (uint256 priceImpact)
    {
        require(amountIn > 0, "Amount must be greater than 0"); // TODO: require(revert)

        address pair = factory.getPair(tokenIn, tokenOut);
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(pair);
        (uint112 reserve0, uint112 reserve1,) = uniswapPair.getReserves();
        require(reserve0 > 0 && reserve1 > 0, "Invalid reserves");

        // Determine which token is token0 and set reserves accordingly
        (uint256 reserveIn, uint256 reserveOut) = tokenIn == uniswapPair.token0()
            ? (uint256(reserve0), uint256(reserve1))
            : (uint256(reserve1), uint256(reserve0));

        // Calculate amount out using Uniswap V2 formula
        uint256 amountInWithFee = amountIn * 997; // 0.3% fee
        uint256 numerator = amountInWithFee * reserveOut;
        uint256 denominator = reserveIn * 1000 + amountInWithFee;
        uint256 amountOut = numerator / denominator;

        // Calculate spot price (price before swap)
        uint256 spotPrice = (reserveOut * PRECISION) / reserveIn;

        // Calculate execution price (price after swap)
        uint256 executionPrice = (amountOut * PRECISION) / amountIn;

        // Calculate price impact
        if (executionPrice >= spotPrice) {
            return 0;
        }

        priceImpact = ((spotPrice - executionPrice) * PRECISION) / spotPrice;

        return priceImpact;
    }

    function executeSwap(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address tokenReceiver,
        uint256 deadline
    ) internal {
        try routerV2.swapExactTokensForTokens(amountIn, amountOutMin, path, tokenReceiver, deadline) returns (
            uint256[] memory amounts
        ) {
            // great, the swap should be a profitable one
        } catch {
            // pull required weth (as per the premium needed) to compensate from the contract
        }
    }

    function withdrawDust() external nonReentrant onlyOwner {
        uint256 balance = address(this).balance;
        (bool success,) = owner().call{value: balance}("");
        if (!success) {
            revert FlashLoan__TransferFailed(0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE, owner()); // For native token
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
