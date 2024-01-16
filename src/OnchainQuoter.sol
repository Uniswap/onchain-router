// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {Quoter} from "v3-view/contracts/Quoter.sol";
import {IQuoter} from "v3-view/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV2Library} from "v2-periphery/contracts/libraries/UniswapV2Library.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";

import {IOnchainQuoter} from "./interfaces/IOnchainQuoter.sol";

contract OnchainQuoter {
    Quoter quoter;
    IUniswapV3Factory v3Factory;
    address v2Factory;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    constructor(address _quoterAddress, address _v3Factory, address _v2Factory) {
        quoter = Quoter(_quoterAddress);
        v3Factory = IUniswapV3Factory(_v3Factory);
        v2Factory = _v2Factory;
    } 
    function quoteV3(IOnchainQuoter.Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        IQuoter.QuoteExactInputSingleWithPoolParams memory params = IQuoter.QuoteExactInputSingleWithPoolParams({
            tokenIn: path.tokenIn,
            tokenOut: path.tokenOut,
            amountIn: amountIn,
            pool: path.pool,
            fee: path.fee,
            sqrtPriceLimitX96: 0
        });

        (amountOut,,) = quoter.quoteExactInputSingleWithPool(params);
    }

    function quoteV2(IOnchainQuoter.Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        (address token0,) = UniswapV2Library.sortTokens(path.tokenIn, path.tokenOut);
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(path.pool).getReserves();

        // we need to reverse the tokens
        if (token0 != path.tokenIn) {
            (reserveA, reserveB) = (reserveB, reserveA);
        }

        amountOut = UniswapV2Library.getAmountOut(amountIn, reserveA, reserveB);
    }

    function quotePath(IOnchainQuoter.Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        amountOut = path.version ? quoteV3(path, amountIn) : quoteV2(path, amountIn);
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

    function amtOutFromQuote(IOnchainQuoter.Quote memory quote) public view returns (uint256 amtOut) {
        uint256 amtIn = quote.amtIn;
        IOnchainQuoter.Path[] memory paths = quote.path;

        for (uint256 i = 0; i < paths.length; i++) {
            if (i != 0) {
                amtOut = amtIn;
            }
            amtOut = quotePath(paths[i], amtIn); 
        }
    }

    function generateV3Paths(IOnchainQuoter.Inputs memory quote) public view returns (IOnchainQuoter.Path[] memory paths, uint256 validPaths) {
        uint24[4] memory fees = currentV3FeeTiers;

        paths = new IOnchainQuoter.Path[](fees.length);

        (address[] memory pools) = getV3Pools(quote.tokenIn, quote.tokenOut, fees);

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                IOnchainQuoter.Path memory path = IOnchainQuoter.Path({
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

    function generateV2Path(IOnchainQuoter.Inputs memory quote) public view returns (IOnchainQuoter.Path[] memory path, uint256 validPaths) {
        (address token0, address token1) = UniswapV2Library.sortTokens(quote.tokenIn, quote.tokenOut);
        address v2Pool = IUniswapV2Factory(v2Factory).getPair(token0, token1);

        path = new IOnchainQuoter.Path[](1);
        if (v2Pool != address(0)) {
            path[validPaths] = IOnchainQuoter.Path({
                tokenIn: quote.tokenIn,
                tokenOut: quote.tokenOut,
                pool: v2Pool,
                fee: uint24(3000),
                version: false
            });

            validPaths++;
        }
    }

    function generateQuoteFromPath(IOnchainQuoter.Path[] memory path, uint256 amtIn) public pure returns (IOnchainQuoter.Quote memory quote) {
        quote = IOnchainQuoter.Quote({path: path, amtIn: amtIn});
    }

    function addPaths(IOnchainQuoter.Path[] memory path1, IOnchainQuoter.Path[] memory path2) public pure returns (IOnchainQuoter.Path[] memory path) {
        uint256 length = path1.length + path2.length;
        path = new IOnchainQuoter.Path[](length);

        for (uint256 i = 0; i < path1.length; i++) {
            path[i] = path1[i];
        }

        for (uint256 i = 0; i < path2.length; i++) {
            path[i + path1.length] = path2[i];
        }
    }

    function addQuotes(IOnchainQuoter.Quote memory quote1, IOnchainQuoter.Quote memory quote2) public pure returns (IOnchainQuoter.Quote memory quote) {
        quote.path = addPaths(quote1.path, quote2.path);
        quote.amtIn = quote1.amtIn;
    }

    function generate1HopQuotes(IOnchainQuoter.Inputs memory inputs)
        public
        view
        returns (IOnchainQuoter.Quote[] memory quotes, uint256 validQuotes)
    {
        (IOnchainQuoter.Path[] memory v2Path, uint256 validV2Paths) = generateV2Path(inputs);
        (IOnchainQuoter.Path[] memory v3Paths, uint256 validV3Paths) = generateV3Paths(inputs);

        uint256 totalPaths = validV2Paths + validV3Paths;
        quotes = new IOnchainQuoter.Quote[](totalPaths);

        if (validV2Paths != 0) {
            quotes[validQuotes] = generateQuoteFromPath(v2Path, inputs.amountIn);
            validQuotes++;
        }

        if (validV3Paths != 0) {
            for (uint256 i = 0; i < validV3Paths; i++) {
                IOnchainQuoter.Path[] memory pathArray = new IOnchainQuoter.Path[](1);
                pathArray[0] = v3Paths[i];

                quotes[validQuotes] = generateQuoteFromPath(pathArray, inputs.amountIn);
                validQuotes++;
            }
        }
    }

    function generateMultiHop(IOnchainQuoter.Inputs memory quote) public view returns (IOnchainQuoter.Quote memory finalQuote, uint256 amtOut) {
        // here i could set multiple tokens as the intermediate token and send it
        IOnchainQuoter.Inputs memory quoteFirstLeg = IOnchainQuoter.Inputs({amountIn: quote.amountIn, tokenIn: quote.tokenIn, tokenOut: WETH});
        (IOnchainQuoter.Quote[] memory quotesLeg1,) = generate1HopQuotes(quoteFirstLeg);
        (IOnchainQuoter.Quote memory bestQuoteLeg1, uint256 bestAmtOut1) = findBestQuote(quotesLeg1);

        IOnchainQuoter.Inputs memory quoteSecondLeg = IOnchainQuoter.Inputs({amountIn: bestAmtOut1, tokenIn: WETH, tokenOut: quote.tokenOut});
        (IOnchainQuoter.Quote[] memory quotesLeg2,) = generate1HopQuotes(quoteSecondLeg);
        (IOnchainQuoter.Quote memory bestQuoteLeg2, uint256 bestAmtOut2) = findBestQuote(quotesLeg2);

        IOnchainQuoter.Path[] memory path = new IOnchainQuoter.Path[](2);
        path[0] = bestQuoteLeg1.path[0];
        path[1] = bestQuoteLeg2.path[0];

       finalQuote = generateQuoteFromPath(path, quote.amountIn);
       amtOut = bestAmtOut2;
    }

    function findBestQuote(IOnchainQuoter.Quote[] memory quotes) public view returns (IOnchainQuoter.Quote memory bestQuote, uint256 bestAmtOut) {
        uint256 amtOut;
  
        for (uint256 i = 0; i < quotes.length; i++) {
            amtOut = amtOutFromQuote(quotes[i]);

            if (amtOut > bestAmtOut) {
                bestQuote = quotes[i];
                bestAmtOut = amtOut;
            }
        }
    }
}