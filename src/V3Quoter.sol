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

contract V3Quoter is IV3Quoter {
    using QuoterMath for *;
    using LowGasSafeMath for uint256;
    using LowGasSafeMath for int256;
    using SafeCast for uint256;
    using SafeCast for int256;
    using Path for bytes;

    IUniswapV3Factory public immutable v3Factory;

    constructor(address _v3Factory) {
        v3Factory = IUniswapV3Factory(_v3Factory);
    }

    function getPool(address tokenA, address tokenB, uint24 fee) private view returns (address pool) {
        pool = PoolAddress.computeAddress(address(v3Factory), PoolAddress.getPoolKey(tokenA, tokenB, fee));
    }

    /// @inheritdoc IV3Quoter
    function v3QuoteExactInputSingleWithPool(QuoteExactInputSingleWithPoolParams memory params)
        public
        view
        override
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

    /// @inheritdoc IV3Quoter
    function v3QuoteExactInputSingle(QuoteExactInputSingleParams memory params)
        public
        view
        override
        returns (uint256 amountReceived, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        address pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        QuoteExactInputSingleWithPoolParams memory poolParams = QuoteExactInputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amountIn: params.amountIn,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountReceived, sqrtPriceX96After, initializedTicksCrossed) = v3QuoteExactInputSingleWithPool(poolParams);
    }

    /// @inheritdoc IV3Quoter
    function v3QuoteExactInput(bytes memory path, uint256 amountIn)
        public
        view
        override
        returns (uint256 amountOut, uint160[] memory sqrtPriceX96AfterList, uint32[] memory initializedTicksCrossedList)
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenIn, address tokenOut, uint24 fee) = path.decodeFirstPool();

            // the outputs of prior swaps become the inputs to subsequent ones
            (uint256 _amountOut, uint160 _sqrtPriceX96After, uint32 initializedTicksCrossed) = v3QuoteExactInputSingle(
                QuoteExactInputSingleParams({
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

    /// @inheritdoc IV3Quoter
    function v3QuoteExactOutputSingleWithPool(QuoteExactOutputSingleWithPoolParams memory params)
        public
        view
        override
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

    /// @inheritdoc IV3Quoter
    function v3QuoteExactOutputSingle(QuoteExactOutputSingleParams memory params)
        public
        view
        override
        returns (uint256 amountIn, uint160 sqrtPriceX96After, uint32 initializedTicksCrossed)
    {
        address pool = getPool(params.tokenIn, params.tokenOut, params.fee);

        QuoteExactOutputSingleWithPoolParams memory poolParams = QuoteExactOutputSingleWithPoolParams({
            tokenIn: params.tokenIn,
            tokenOut: params.tokenOut,
            amount: params.amount,
            fee: params.fee,
            pool: pool,
            sqrtPriceLimitX96: 0
        });

        (amountIn, sqrtPriceX96After, initializedTicksCrossed) = v3QuoteExactOutputSingleWithPool(poolParams);
    }

    /// @inheritdoc IV3Quoter
    function v3QuoteExactOutput(bytes memory path, uint256 amountOut)
        public
        view
        override
        returns (uint256 amountIn, uint160[] memory sqrtPriceX96AfterList, uint32[] memory initializedTicksCrossedList)
    {
        sqrtPriceX96AfterList = new uint160[](path.numPools());
        initializedTicksCrossedList = new uint32[](path.numPools());

        uint256 i = 0;
        while (true) {
            (address tokenOut, address tokenIn, uint24 fee) = path.decodeFirstPool();

            // the inputs of prior swaps become the outputs of subsequent ones
            (uint256 _amountIn, uint160 _sqrtPriceX96After, uint32 _initializedTicksCrossed) = v3QuoteExactOutputSingle(
                QuoteExactOutputSingleParams({
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
