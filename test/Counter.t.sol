// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {Quoter} from "v3-view/contracts/Quoter.sol";
import {IQuoter} from "v3-view/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract RouterTest is Test {
    uint256 mainnetFork;
    Quoter quoter;
    IUniswapV3Factory factory;

    struct Quote {
        uint256 amountIn;
        address tokenIn;
        address tokenOut;
    }

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        quoter = new Quoter(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    }

    function getV3Pools(address token0, address token1, uint24[4] memory fees) public view returns (address[] memory pools) {
        pools = new address[](fees.length);

        address poolAddress;
        for (uint256 i = 0; i < fees.length; i++) {
            pools[i] = factory.getPool(token0, token1, fees[i]);
        }
    }

    function test_Increment() public {
        uint24[4] memory fees = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

        Quote memory quote = Quote({amountIn: 1e18,
                             tokenIn: 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2,
                             tokenOut: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48
                            });

        (address[] memory pools)  = getV3Pools(quote.tokenIn, quote.tokenOut, fees);

        uint256[] memory amountsOut = new uint256[](fees.length);
        
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




        assertEq(true, true);
    }
}
