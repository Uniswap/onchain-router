// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IFeeOnTransferDetector} from "../src/interfaces/IFeeOnTransferDetector.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {PathGenerator} from "./base/PathGenerator.sol";
import {QuoteLibrary} from "./libraries/QuoteLibrary.sol";
import {SwapParams, Pool, SwapHop, Quote} from "./base/OnchainRouterStructs.sol";
import {OnchainRouterImmutables} from "./base/OnchainRouterImmutables.sol";
import {IV3Quoter} from "./interfaces/IV3Quoter.sol";
import {V3Quoter} from "./V3Quoter.sol";
import {V2Quoter} from "./V2Quoter.sol";

contract OnchainRouter is OnchainRouterImmutables, V3Quoter, V2Quoter, PathGenerator {
    using QuoteLibrary for Quote;
    using QuoteLibrary for Pool;

    address public immutable WETH;

    constructor(address _v2Factory, address _v3Factory, address _weth)
        OnchainRouterImmutables(_v2Factory, _v3Factory)
        PathGenerator(_v3Factory)
    {
        WETH = _weth;
    }

    /// @notice finds the best route for a given exact input swap
    /// @param params struct containing tokenIn, tokenOut, and amountSpecified
    /// @dev returns the best quote
    function routeExactInput(SwapParams memory params) public view returns (Quote memory bestQuote) {
        if (params.tokenIn == WETH || params.tokenOut == WETH) {
            return routeExactInputSingle(params);
        }

        Quote memory multi = routeExactInputMulti(params, WETH);
        Quote memory single = routeExactInputSingle(params);
        return multi.better(single);
    }

    /// @notice finds the best route for a given exact output swap
    /// @param params struct containing tokenIn, tokenOut, and amountSpecified
    /// @dev returns the best quote
    function routeExactOutput(SwapParams memory params) public view returns (Quote memory bestQuote) {
        if (params.tokenIn == WETH || params.tokenOut == WETH) {
            return routeExactOutputSingle(params);
        }

        Quote memory multi = routeExactOutputMulti(params, WETH);
        Quote memory single = routeExactOutputSingle(params);
        return multi.better(single);
    }

    // ----- INTERNAL HELPERS -----

    /// @notice finds all routes from input to intermediate and from intermediate to output
    /// @dev returns the best route
    function routeExactInputMulti(SwapParams memory params, address intermediate)
        internal
        view
        returns (Quote memory bestQuote)
    {
        Quote memory inputToIntermediate = routeExactInputSingle(
            SwapParams({tokenIn: params.tokenIn, tokenOut: intermediate, amountSpecified: params.amountSpecified})
        );
        Quote memory intermediateToOutput = routeExactInputSingle(
            SwapParams({
                tokenIn: intermediate,
                tokenOut: params.tokenOut,
                amountSpecified: inputToIntermediate.amountOut
            })
        );
        bestQuote = inputToIntermediate.combine(intermediateToOutput);
    }

    /// @notice finds all routes from output to intermediate and from intermediate to input
    /// @dev returns the best route
    function routeExactOutputMulti(SwapParams memory params, address intermediate)
        internal
        view
        returns (Quote memory bestQuote)
    {
        Quote memory outputToIntermediate = routeExactOutputSingle(
            SwapParams({tokenIn: intermediate, tokenOut: params.tokenOut, amountSpecified: params.amountSpecified})
        );
        Quote memory intermediateToInput = routeExactOutputSingle(
            SwapParams({tokenIn: params.tokenIn, tokenOut: intermediate, amountSpecified: outputToIntermediate.amountIn})
        );

        bestQuote = intermediateToInput.combine(outputToIntermediate);
    }

    /// @dev finds and quotes all single pools for a given single hop
    /// @dev and returns the pool with the best quote
    function routeExactInputSingle(SwapParams memory params) internal view returns (Quote memory bestQuote) {
        Pool[] memory pools = PathGenerator.generatePaths(params.tokenIn, params.tokenOut);

        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory pool = pools[i];
            SwapHop memory swap = SwapHop({pool: pool, amountSpecified: params.amountSpecified});
            uint256 amountOut = pool.version ? v3QuoteExactIn(swap) : v2QuoteExactIn(swap);

            if (amountOut > bestQuote.amountOut) {
                bestQuote = pool.createQuoteSingle(params.amountSpecified, amountOut);
            }
        }
    }

    /// @dev finds and quotes all single pools for a given single hop
    /// @dev and returns the pool with the best quote
    function routeExactOutputSingle(SwapParams memory params) internal view returns (Quote memory bestQuote) {
        Pool[] memory pools = PathGenerator.generatePaths(params.tokenIn, params.tokenOut);

        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory pool = pools[i];
            SwapHop memory swap = SwapHop({pool: pool, amountSpecified: params.amountSpecified});
            uint256 amountIn = pool.version ? v3QuoteExactOut(swap) : v2QuoteExactOut(swap);

            if (amountIn < bestQuote.amountIn) {
                bestQuote = pool.createQuoteSingle(amountIn, params.amountSpecified);
            }
        }
    }
}
