// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {OnchainRouter} from "../src/OnchainRouter.sol";
import {SwapParams, Quote} from "../src/base/OnchainRouterStructs.sol";
import {IFeeOnTransferDetector} from "../src/interfaces/IFeeOnTransferDetector.sol";

contract RouterForkTest is Test {
    OnchainRouter onchainRouter;
    IUniswapV3Factory v3Factory;
    IUniswapV2Factory v2Factory;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    function setUp() public {
        vm.createSelectFork(vm.envString("MAINNET_RPC_URL"));

        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v2Factory = IUniswapV2Factory(0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f);

        onchainRouter = new OnchainRouter(address(v2Factory), address(v3Factory), WETH);
    }

    function test_getsFeeTiers() public {
        assertTrue(onchainRouter.feeTiers(0) == 100);
        assertTrue(onchainRouter.feeTiers(1) == 500);
        assertTrue(onchainRouter.feeTiers(2) == 3000);
        assertTrue(onchainRouter.feeTiers(3) == 10000);
        vm.expectRevert();
        onchainRouter.feeTiers(4);
    }

    function test_routeHarryPotter() public {
        SwapParams memory request = SwapParams({
            amountSpecified: 1000 * 1e6,
            tokenIn: USDC,
            tokenOut: 0x72e4f9F808C49A2a61dE9C5896298920Dc4EEEa9
        });

        Quote memory quote = onchainRouter.routeExactInput(request);
        console.log(quote.amountOut);
        console.log(quote.path.length);
        console.log(quote.path[0].pool);
        console.log(quote.path[1].pool);

        //address path = quotes[0].path[0].pool;
        // console.log(validQuotes);
        //
        // Quote memory multihopQuote;
        // uint256 multihopOut;
        // if ((quote.tokenIn != WETH) && (quote.tokenOut != WETH)) {
        //     (multihopQuote, multihopOut) = onchainRouter.generateAndPriceMultiHop(quote);
        // }
        // (Quote memory singehopQuote, uint256 singlehopOut) = onchainRouter.findBestQuote(quotes);
        //
        // if (singlehopOut > multihopOut) {
        //     console.log("single");
        //     console.log(singlehopOut - multihopOut);
        //     console.log(singlehopOut);
        //     address addr = singehopQuote.path[0].pool;
        //     console2.log(addr);
        // } else {
        //     console.log("multi");
        //     console.log(multihopOut - singlehopOut);
        //     console.log(multihopOut);
        //     address addr = multihopQuote.path[0].pool;
        //     console2.log(addr);
        //     addr = multihopQuote.path[1].pool;
        //     console2.log(addr);
        // }
        // assertEq(true, true);
    }
}
