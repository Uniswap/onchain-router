// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.7.6;

import {Test, console, console2} from "forge-std/Test.sol";
import {Quoter} from "v3-view/contracts/Quoter.sol";
import {IQuoter} from "v3-view/contracts/interfaces/IQuoter.sol";
import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";

contract CounterTest is Test {
    Counter public counter;

    function setUp() public {
        mainnetFork = vm.createFork(vm.envString("MAINNET_RPC_URL"));
        vm.selectFork(mainnetFork);

        quoterV3 = new Quoter(0x1F98431c8aD98523631AE4a59f267346ea31F984);
        factory = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);
    }

    function test_Increment() public {
        address token0 = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
        address token1 = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        uint24[] fees = [100, 500, 3000, 10000];

        address poolAddress;
        for (i = 0; i <= fees.length; i++) {
            poolAddress = factory.getPool(token0, token1, fees[i]);
        }

        console.log(poolAddress);
        
    }
}
