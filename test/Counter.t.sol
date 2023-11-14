// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {Quoter} from "v3-view/contracts/Quoter.sol";
import {IQuoter} from "v3-view/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {UniswapV2Library} from "v2-periphery/contracts/libraries/UniswapV2Library.sol";

contract RouterTest is Test {
    uint256 mainnetFork;
    Quoter quoter;
    IUniswapV3Factory v3Factory;
    address v2Factory;

    struct Quote {
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        quoter = new Quoter(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    }

    function getV3Pools(address token0, address token1, uint24[4] memory fees) public view returns (address[] memory pools) {
        pools = new address[](fees.length);

        for (uint256 i = 0; i < fees.length; i++) {
            pools[i] = v3Factory.getPool(token0, token1, fees[i]);
        }
    }

    function quoteV3(Quote memory quote) public view returns (uint256[] memory amountsOut) {
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

        (address[] memory pools)  = getV3Pools(quote.tokenIn, quote.tokenOut, fees);

        amountsOut = new uint256[](fees.length);
        
        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                IQuoter.QuoteExactInputSingleParams memory params = IQuoter.QuoteExactInputSingleParams({tokenIn: quote.tokenIn,
                                                                                                tokenOut: quote.tokenOut,
                                                                                                amountIn: quote.amountIn,
                                                                                                fee: fees[i], 
                                                                                                sqrtPriceLimitX96: 0});

                (uint256 amountOut,,) = quoter.quoteExactInputSingle(params);
                amountsOut[i] = amountOut;
                console.log(amountOut);
            }
        }
    }

    function quoteV2(Quote memory quote) public view returns (uint256 amountOut) {
        (address token0, address token1) = UniswapV2Library.sortTokens(quote.tokenIn, quote.tokenOut);
        (uint256 reserveA, uint256 reserveB) = UniswapV2Library.getReserves(v2Factory, token0, token1);
        
        // we need to reverse the tokens
        if (token0 != quote.tokenIn) {
            (reserveA, reserveB) = (reserveB, reserveA);
        }
        uint256 amountOut = UniswapV2Library.getAmountOut(quote.amountIn, reserveA, reserveB);
    
    }

    function test_Increment() public {
        Quote memory quote = Quote({amountIn: 1e18,
                             tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                             tokenOut: 0x72e4f9f808c49a2a61de9c5896298920dc4eeea9
                            });


        uint256[] memory v3AmountsOut = quoteV3(quote);
        for (uint256 i = 0; i < v3AmountsOut.length; i++) {
            console.log(v3AmountsOut[i]);
        }
        uint256 v2AmountOut = quoteV2(quote);
       
        console.log(V2amountOut);

        assertEq(true, true);
    }
}
