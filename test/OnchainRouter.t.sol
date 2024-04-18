// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {Test, console, console2} from "forge-std/Test.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {OnchainRouter} from "../src/OnchainRouter.sol";
import {ExactInputRouteRequestParams, Quote} from "../src/base/OnchainRouterStructs.sol";
import {IFeeOnTransferDetector} from "../src/interfaces/IFeeOnTransferDetector.sol";

contract RouterTest is Test {
    uint256 mainnetFork;
    OnchainRouter onchainRouter;
    IUniswapV3Factory v3Factory;
    address v2Factory;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        v3Factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        v2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;

        onchainRouter = new OnchainRouter(address(v3Factory), v2Factory);
    }

    function test_Increment() public {
        ExactInputRouteRequestParams memory quote = ExactInputRouteRequestParams({
            amountIn: 1000 * 1e6,
            tokenIn: 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48,
            tokenOut: 0x72e4f9F808C49A2a61dE9C5896298920Dc4EEEa9
        });

        (Quote[] memory quotes, uint256 validQuotes) = onchainRouter.generate1HopQuotes(quote);

        //address path = quotes[0].path[0].pool;
        console.log(validQuotes);

        Quote memory multihopQuote;
        uint256 multihopOut;
        if ((quote.tokenIn != WETH) && (quote.tokenOut != WETH)) {
            (multihopQuote, multihopOut) = onchainRouter.generateAndPriceMultiHop(quote);
        }
        (Quote memory singehopQuote, uint256 singlehopOut) = onchainRouter.findBestQuote(quotes);

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

    function test_FOT() public {
        address unibot = 0xf819d9Cb1c2A819Fd991781A822dE3ca8607c3C9;
        address FOTDetector = 0x19C97dc2a25845C7f9d1d519c8C2d4809c58b43f;

        IFeeOnTransferDetector detector = IFeeOnTransferDetector(FOTDetector);
        IFeeOnTransferDetector.TokenFees memory result = detector.validate(unibot, WETH, 1e20);

        console2.log(result.buyFeeBps);
        console2.log(result.sellFeeBps);
    }
}
