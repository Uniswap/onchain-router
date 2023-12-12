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

contract RouterTest is Test {
    uint256 mainnetFork;
    Quoter quoter;
    IUniswapV3Factory v3Factory;
    address v2Factory;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    struct Inputs {
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
    }

    struct Path {
        address tokenIn;
        address tokenOut;
        uint24 fee;
        address pool;
        bool version;
    }

    struct Quote {
        Path[] path;
        uint256 amtIn;
    }

    struct Route {
        Path[] path;
        uint256 amtIn;
        uint256 amtOut;
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);
        
        quoter = new Quoter(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
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

    function quoteV3(Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
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

    function quoteV2(Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        (address token0,) = UniswapV2Library.sortTokens(path.tokenIn, path.tokenOut);
        (uint256 reserveA, uint256 reserveB,) = IUniswapV2Pair(path.pool).getReserves();

        // we need to reverse the tokens
        if (token0 != path.tokenIn) {
            (reserveA, reserveB) = (reserveB, reserveA);
        }

        amountOut = UniswapV2Library.getAmountOut(amountIn, reserveA, reserveB);
    }

    function quotePath(Path memory path, uint256 amountIn) public view returns (uint256 amountOut) {
        amountOut = path.version ? quoteV3(path, amountIn) :quoteV2(path, amountIn);
    }
    
    function amtOutFromQuote(Quote memory quote) public view returns (uint256 amtOut) {
        uint256 amtIn = quote.amtIn;
        Path[] memory paths = quote.path;

        for (uint256 i = 0; i < paths.length; i++) {
            if (i != 0) {
                amtOut = amtIn;
            }
            amtOut = quotePath(paths[i], amtIn); 
        }
    }

    function generateV3Paths(Inputs memory quote) public view returns (Path[] memory paths, uint256 validPaths) {
        uint24[4] memory fees = currentV3FeeTiers;

        paths = new Path[](fees.length);

        (address[] memory pools) = getV3Pools(quote.tokenIn, quote.tokenOut, fees);

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                Path memory path = Path({
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

    function generateV2Path(Inputs memory quote) public view returns (Path[] memory path, uint256 validPaths) {
        (address token0, address token1) = UniswapV2Library.sortTokens(quote.tokenIn, quote.tokenOut);
        address v2Pool = IUniswapV2Factory(v2Factory).getPair(token0, token1);

        path = new Path[](1);
        if (v2Pool != address(0)) {
            path[validPaths] = Path({
                tokenIn: quote.tokenIn,
                tokenOut: quote.tokenOut,
                pool: v2Pool,
                fee: uint24(3000),
                version: false
            });

            validPaths++;
        }
    }

    function generateQuoteFromPath(Path[] memory path, uint256 amtIn) public pure returns (Quote memory quote) {
        quote = Quote({path: path, amtIn: amtIn});
    }

    function addPaths(Path[] memory path1, Path[] memory path2) public pure returns (Path[] memory path) {
        uint256 length = path1.length + path2.length;
        path = new Path[](length);

        for (uint256 i = 0; i < path1.length; i++) {
            path[i] = path1[i];
        }

        for (uint256 i = 0; i < path2.length; i++) {
            path[i + path1.length] = path2[i];
        }
    }

    function addQuotes(Quote memory quote1, Quote memory quote2) public pure returns (Quote memory quote) {
        quote.path = addPaths(quote1.path, quote2.path);
        quote.amtIn = quote1.amtIn;
    }

    function generate1HopQuotes(Inputs memory inputs)
        public
        view
        returns (Quote[] memory quotes, uint256 validQuotes)
    {
        (Path[] memory v2Path, uint256 validV2Paths) = generateV2Path(inputs);
        (Path[] memory v3Paths, uint256 validV3Paths) = generateV3Paths(inputs);

        uint256 totalPaths = validV2Paths + validV3Paths;
        quotes = new Quote[](totalPaths);

        if (validV2Paths != 0) {
            quotes[validQuotes] = generateQuoteFromPath(v2Path, inputs.amountIn);
            validQuotes++;
        }

        if (validV3Paths != 0) {
            for (uint256 i = 0; i < validV3Paths; i++) {
                Path[] memory pathArray = new Path[](1);
                pathArray[0] = v3Paths[i];

                quotes[validQuotes] = generateQuoteFromPath(pathArray, inputs.amountIn);
                validQuotes++;
            }
        }
    }

    function generateMultiHop(Inputs memory quote) public view returns (Quote memory finalQuote, uint256 amtOut) {
        // here i could set multiple tokens as the intermediate token and send it
        Inputs memory quoteFirstLeg = Inputs({amountIn: quote.amountIn, tokenIn: quote.tokenIn, tokenOut: WETH});
        (Quote[] memory quotesLeg1, uint256 validQuotesLeg1) = generate1HopQuotes(quoteFirstLeg);
        (Quote memory bestQuoteLeg1, uint256 bestAmtOut1) = findBestQuote(quotesLeg1);

        Inputs memory quoteSecondLeg = Inputs({amountIn: bestAmtOut1, tokenIn: WETH, tokenOut: quote.tokenOut});
        (Quote[] memory quotesLeg2, uint256 validQuotesLeg2) = generate1HopQuotes(quoteSecondLeg);
        (Quote memory bestQuoteLeg2, uint256 bestAmtOut2) = findBestQuote(quotesLeg2);

        Path[] memory path = new Path[](2);
        path[0] = bestQuoteLeg1.path[0];
        path[1] = bestQuoteLeg2.path[0];

       finalQuote = generateQuoteFromPath(path, quote.amountIn);
       amtOut = bestAmtOut2;
    }

    function findBestQuote(Quote[] memory quotes) public view returns (Quote memory bestQuote, uint256 bestAmtOut) {
        uint256 amtOut;
  
        for (uint256 i = 0; i < quotes.length; i++) {
            amtOut = amtOutFromQuote(quotes[i]);

            if (amtOut > bestAmtOut) {
                bestQuote = quotes[i];
                bestAmtOut = amtOut;
            }
        }
    }

    function test_Increment() public {
        Inputs memory quote = Inputs({
            amountIn: 1000 * 1e6,
            tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            tokenOut: 0x72e4f9F808C49A2a61dE9C5896298920Dc4EEEa9
        });

        (Quote[] memory quotes, uint256 validQuotes) = generate1HopQuotes(quote);

        //address path = quotes[0].path[0].pool;
        console.log(validQuotes);

        
        Quote memory multihopQuote;
        uint256 multihopOut;
        if ((quote.tokenIn != WETH) && (quote.tokenOut != WETH)) {
            (multihopQuote, multihopOut) = generateMultiHop(quote);
        }
        (Quote memory singehopQuote, uint256 singlehopOut) = findBestQuote(quotes);

        if (singlehopOut > multihopOut) {
            console.log("single");
            console.log(singlehopOut - multihopOut);
            console.log(singlehopOut);
            address addr = singehopQuote.path[0].pool;
            console2.log(addr);
        } else {
            console.log("multi");
            console.log(multihopOut - singlehopOut);
            console.log(multihopOut);
            address addr = multihopQuote.path[0].pool;
            console2.log(addr);
            addr = multihopQuote.path[1].pool;
            console2.log(addr);
        }
        assertEq(true, true);
    }
}
