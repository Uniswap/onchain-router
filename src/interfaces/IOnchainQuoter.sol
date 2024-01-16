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

contract IOnchainQuoter {
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
}