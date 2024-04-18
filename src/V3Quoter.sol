// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "v3-core/contracts/interfaces/IUniswapV3Pool.sol";
import {SwapMath} from "v3-core/contracts/libraries/SwapMath.sol";
import {FullMath} from "v3-core/contracts/libraries/FullMath.sol";
import {TickMath} from "v3-core/contracts/libraries/TickMath.sol";
import "v3-core/contracts/libraries/LowGasSafeMath.sol";
import "v3-core/contracts/libraries/SafeCast.sol";
import "v3-periphery/contracts/libraries/Path.sol";
import {SqrtPriceMath} from "v3-core/contracts/libraries/SqrtPriceMath.sol";
import {LiquidityMath} from "v3-core/contracts/libraries/LiquidityMath.sol";
import {PoolAddress} from "v3-view/contracts/libraries/PoolAddress.sol";
import {QuoterMath} from "v3-view/contracts/libraries/QuoterMath.sol";
import {PoolTickBitmap} from "v3-view/contracts/libraries/PoolTickBitmap.sol";
import {IV3Quoter} from "./interfaces/IV3Quoter.sol";
import {OnchainRouterImmutables} from "./base/OnchainRouterImmutables.sol";
import {SwapHop} from "./base/OnchainRouterStructs.sol";

abstract contract V3Quoter is OnchainRouterImmutables {
    using QuoterMath for *;
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Path for bytes;

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (address pool) {
        pool = PoolAddress.computeAddress(address(v3Factory), PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    function v3QuoteExactIn(SwapHop memory swap) internal view returns (uint256 amountOut) {
        IV3Quoter.QuoteExactInputSingleWithPoolParams memory params = IV3Quoter.QuoteExactInputSingleWithPoolParams({
            tokenIn: swap.pool.tokenIn,
            tokenOut: swap.pool.tokenOut,
            amountIn: swap.amountSpecified,
            pool: swap.pool.pool,
            fee: swap.pool.fee,
            sqrtPriceLimitX96: 0
        });

        (amountOut,,) = v3QuoteExactInputSingleWithPool(params);
    }

    function v3QuoteExactOut(SwapHop memory swap) internal view returns (uint256 amountIn) {
        IV3Quoter.QuoteExactOutputSingleWithPoolParams memory params = IV3Quoter.QuoteExactOutputSingleWithPoolParams({
            tokenIn: swap.pool.tokenIn,
            tokenOut: swap.pool.tokenOut,
            amount: swap.amountSpecified,
            pool: swap.pool.pool,
            fee: swap.pool.fee,
            sqrtPriceLimitX96: 0
        });

        (amountIn,,) = v3QuoteExactOutputSingleWithPool(params);
    }

    // ---------------- PRIVATE HELPERS ----------------

    function v3QuoteExactInputSingleWithPool(IV3Quoter.QuoteExactInputSingleWithPoolParams memory params)
        private
        view
        returns (uint256 amountReceived, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        int256 amount0;
        int256 amount1;

        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);

        // we need to pack a few variables to get under the stack limit
        QuoterMath.QuoteParams memory quoteParams = QuoterMath.QuoteParams({
            zeroForOne: zeroForOne,
            fee: params.fee,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96,
            exactInput: false
        });

        (amount0, amount1, sqrtPriceX96After, initializedTicksCrossed) =
            QuoterMath.quote(pool, params.amountIn.toInt256(), quoteParams);

        amountReceived = amount0 > 0 ? uint256(-amount1) : uint256(-amount0);
    }

    function v3QuoteExactInputSingle(IV3Quoter.QuoteExactInputSingleParams memory params)
        private
        view
        returns (uint256 amountReceived, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        address pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        IV3Quoter.QuoteExactInputSingleWithPoolParams memory poolParams = IV3Quoter.QuoteExactInputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountReceived, sqrtPriceX96After, initializedTicksCrossed) = v3QuoteExactInputSingleWithPool(poolParams);
    }

    function v3QuoteExactInput(bytes memory path, uint256 amountIn)
        private
        view
        returns (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, uint32[] memory initializedTicksCrossedList)
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            // the outputs of prior swaps become the inputs to subsequent ones
            (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 initializedTicksCrossed) = v3QuoteExactInputSingle(
                IV3Quoter.QuoteExactInputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    fee: fee,
                    amountIn: amountIn,
                    sqrtPriceLimitX96: 0
                })
            );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = initializedTicksCrossed;
            amountIn = _amountOut;
            i++;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountIn, sqrtPriceX96AfterList, initializedTicksCrossedList);
            }
        }
    }

    function v3QuoteExactOutputSingleWithPool(IV3Quoter.QuoteExactOutputSingleWithPoolParams memory params)
        private
        view
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        int256 amount0;
        int256 amount1;
        uint256 amountReceived;

        bool zeroForOne = params.tokenIn < params.tokenOut;
        IUniswapV3Pool pool = IUniswapV3Pool(params.pool);

        uint256 amountOutCached = 0;
        // if no price limit has been specified, cache the output amount for comparison in the swap callback
        if (params.sqrtPriceLimitX96 != 0) amountOutCached = params.amount;

        QuoterMath.QuoteParams memory quoteParams = QuoterMath.QuoteParams({
            zeroForOne: zeroForOne,
            exactInput: true, // will be overridden
            fee: params.fee,
            sqrtPriceLimitX96: params.sqrtPriceLimitX96 == 0
                ? (zeroForOne ? TickMath.MIN_SQRT_RATIO + 1 : TickMath.MAX_SQRT_RATIO - 1)
                : params.sqrtPriceLimitX96
        });

        (amount0, amount1, sqrtPriceX96After, initializedTicksCrossed) =
            QuoterMath.quote(pool, -(params.amount.toInt256()), quoteParams);

        amountIn = amount0 > 0 ? uint256(amount0) : uint256(amount1);
        amountReceived = amount0 > 0 ? uint256(-amount1) : uint256(amount0);

        // did we get the full amount?
        if (amountOutCached != 0) require(amountReceived == amountOutCached);
    }

    function v3QuoteExactOutputSingle(IV3Quoter.QuoteExactOutputSingleParams memory params)
        private
        view
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        address pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        IV3Quoter.QuoteExactOutputSingleWithPoolParams memory poolParams = IV3Quoter
            .QuoteExactOutputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amount: params.amount,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountIn, sqrtPriceX96After, initializedTicksCrossed) = v3QuoteExactOutputSingleWithPool(poolParams);
    }

    function v3QuoteExactOutput(bytes memory path, uint256 amountOut)
        private
        view
        returns (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, uint32[] memory initializedTicksCrossedList)
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenOut, address tokenIn, uint24 fee) = path.decodeFirstPool();

            // the inputs of prior swaps become the outputs of subsequent ones
            (uint256 _amountIn, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed) = v3QuoteExactOutputSingle(
                IV3Quoter.QuoteExactOutputSingleParams({
                    tokenIn: tokenIn,
                    tokenOut: tokenOut,
                    amount: amountOut,
                    fee: fee,
                    sqrtPriceLimitX96: 0
                })
            );

            sqrtPriceX96AfterList[i] = _sqrtPriceX96After;
            initializedTicksCrossedList[i] = _initializedTicksCrossed;
            amountOut = _amountIn;
            i++;

            // decide whether to continue or terminate
            if (path.hasMultiplePools()) {
                path = path.skipToken();
            } else {
                return (amountOut, sqrtPriceX96AfterList, initializedTicksCrossedList);
            }
        }
    }
}
