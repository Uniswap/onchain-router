// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IFeeOnTransferDetector} from "../src/interfaces/IFeeOnTransferDetector.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {ExactInputRouteRequestParams, Pool, SwapHop, Quote} from "./base/OnchainRouterStructs.sol";
import {IV3Quoter} from "./interfaces/IV3Quoter.sol";
import {V3Quoter} from "./V3Quoter.sol";
import {V2Quoter} from "./V2Quoter.sol";

contract OnchainRouter is V3Quoter, V2Quoter {
    address v2Factory;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    constructor(address _v3Factory, address _v2Factory) V3Quoter(_v3Factory) {
        v2Factory = _v2Factory;
    }

    function quoteV3(SwapHop memory swap) public view returns (uint256 amountOut) {
        IV3Quoter.QuoteExactInputSingleWithPoolParams memory params = IV3Quoter.QuoteExactInputSingleWithPoolParams({
            tokenIn: swap.pool.tokenIn,
            tokenOut: swap.pool.tokenOut,
            amountIn: swap.amount,
            pool: swap.pool.pool,
            fee: swap.pool.fee,
            sqrtPriceLimitX96: 0
        });

        (amountOut,,) = v3QuoteExactInputSingleWithPool(params);
    }

    function quoteHop(SwapHop memory swap) public view returns (uint256 quote) {
        if (swap.exactIn) {
            quote = swap.pool.version ? quoteV3(swap) : v2QuoteExactIn(swap);
        } else {
            quote = swap.pool.version ? quoteV3(swap) : v2QuoteExactOut(swap);
        }
    }

    function getV3Pools(address token0, address token1, uint24[4] memory fees)
        public
        view
        returns (address[] memory pools)
    {
        pools = new address[](fees.length);

        for (uint256 i = 0; i < fees.length; i++) {
            pools[i] = v3Factory.getPool(token0, token1, fees[i]);
        }
    }

    function amountOutFromQuote(Quote memory quote) public view returns (uint256 amountOut) {
        uint256 amountIn = quote.amountIn;
        Pool[] memory paths = quote.path;

        for (uint256 i = 0; i < paths.length; i++) {
            if (i != 0) {
                amountOut = amountIn;
            }
            amountOut = quoteHop(SwapHop({
                pool: paths[i],
                amount: amountIn,
                exactIn: true
            }));
        }
    }

    function generateV3Paths(ExactInputRouteRequestParams memory quote) public view returns (Pool[] memory paths, uint256 validPaths) {
        uint24[4] memory fees = currentV3FeeTiers;

        paths = new Pool[](fees.length);

        (address[] memory pools) = getV3Pools(quote.tokenIn, quote.tokenOut, fees);

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                Pool memory path = Pool({
                    tokenIn: quote.tokenIn,
                    tokenOut: quote.tokenOut,
                    pool: pools[i],
                    fee: fees[i],
                    version: true
                });
                paths[validPaths] = path;
                validPaths++;
            }
        }
    }

    function generateV2Path(ExactInputRouteRequestParams memory quote) public view returns (Pool[] memory path, uint256 validPaths) {
        (address token0, address token1) = UniswapV2Library.sortTokens(quote.tokenIn, quote.tokenOut);
        address v2Pool = IUniswapV2Factory(v2Factory).getPair(token0, token1);

        path = new Pool[](1);
        if (v2Pool != address(0)) {
            path[validPaths] = Pool({
                tokenIn: quote.tokenIn,
                tokenOut: quote.tokenOut,
                pool: v2Pool,
                fee: uint24(3000),
                version: false
            });

            validPaths++;
        }
    }

    function generateQuoteFromPath(Pool[] memory path, uint256 amountIn) public pure returns (Quote memory quote) {
        quote = Quote({path: path, amountIn: amountIn});
    }

    function addPaths(Pool[] memory path1, Pool[] memory path2) public pure returns (Pool[] memory path) {
        uint256 length = path1.length + path2.length;
        path = new Pool[](length);

        for (uint256 i = 0; i < path1.length; i++) {
            path[i] = path1[i];
        }

        for (uint256 i = 0; i < path2.length; i++) {
            path[i + path1.length] = path2[i];
        }
    }

    function addQuotes(Quote memory quote1, Quote memory quote2) public pure returns (Quote memory quote) {
        quote.path = addPaths(quote1.path, quote2.path);
        quote.amountIn = quote1.amountIn;
    }

    function generate1HopQuotes(ExactInputRouteRequestParams memory inputs)
        public
        view
        returns (Quote[] memory quotes, uint256 validQuotes)
    {
        (Pool[] memory v2Path, uint256 validV2Paths) = generateV2Path(inputs);
        (Pool[] memory v3Paths, uint256 validV3Paths) = generateV3Paths(inputs);

        uint256 totalPaths = validV2Paths + validV3Paths;
        quotes = new Quote[](totalPaths);

        if (validV2Paths != 0) {
            quotes[validQuotes] = generateQuoteFromPath(v2Path, inputs.amountIn);
            validQuotes++;
        }

        if (validV3Paths != 0) {
            for (uint256 i = 0; i < validV3Paths; i++) {
                Pool[] memory pathArray = new Pool[](1);
                pathArray[0] = v3Paths[i];

                quotes[validQuotes] = generateQuoteFromPath(pathArray, inputs.amountIn);
                validQuotes++;
            }
        }
    }

    function findBestQuote(Quote[] memory quotes) public view returns (Quote memory bestQuote, uint256 bestamountOut) {
        uint256 amountOut;

        for (uint256 i = 0; i < quotes.length; i++) {
            amountOut = amountOutFromQuote(quotes[i]);

            if (amountOut > bestamountOut) {
                bestQuote = quotes[i];
                bestamountOut = amountOut;
            }
        }
    }

    function generateAndPriceSingleHop(ExactInputRouteRequestParams memory quote)
        public
        view
        returns (Quote memory finalQuote, uint256 amountOut)
    {
        (Quote[] memory quotes,) = generate1HopQuotes(quote);
        (finalQuote, amountOut) = findBestQuote(quotes);
    }

    function generateAndPriceMultiHop(ExactInputRouteRequestParams memory quote)
        public
        view
        returns (Quote memory finalQuote, uint256 amountOut)
    {
        // here i could set multiple tokens as the intermediate token and send it
        ExactInputRouteRequestParams memory quoteFirstLeg =
            ExactInputRouteRequestParams({amountIn: quote.amountIn, tokenIn: quote.tokenIn, tokenOut: WETH});
        (Quote[] memory quotesLeg1,) = generate1HopQuotes(quoteFirstLeg);
        (Quote memory bestQuoteLeg1, uint256 bestamountOut1) = findBestQuote(quotesLeg1);

        ExactInputRouteRequestParams memory quoteSecondLeg =
            ExactInputRouteRequestParams({amountIn: bestamountOut1, tokenIn: WETH, tokenOut: quote.tokenOut});
        (Quote[] memory quotesLeg2,) = generate1HopQuotes(quoteSecondLeg);
        (Quote memory bestQuoteLeg2, uint256 bestamountOut2) = findBestQuote(quotesLeg2);

        Pool[] memory path = new Pool[](2);
        path[0] = bestQuoteLeg1.path[0];
        path[1] = bestQuoteLeg2.path[0];

        finalQuote = generateQuoteFromPath(path, quote.amountIn);
        amountOut = bestamountOut2;
    }

    function getBestQuotes(ExactInputRouteRequestParams memory quote)
        public
        view
        returns (Quote memory bestQuote, uint256 bestamountOut, uint256 hops)
    {
        (Quote memory singehopQuote, uint256 singlehopOut) = generateAndPriceSingleHop(quote);

        Quote memory multihopQuote;
        uint256 multihopOut;
        if ((quote.tokenIn != WETH) && (quote.tokenOut != WETH)) {
            (multihopQuote, multihopOut) = generateAndPriceMultiHop(quote);
        }

        if (singlehopOut > multihopOut) {
            bestQuote = singehopQuote;
            bestamountOut = singlehopOut;
            hops = 1;
        } else {
            bestQuote = multihopQuote;
            bestamountOut = multihopOut;
            hops = 2;
        }
    }
}
