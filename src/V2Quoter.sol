// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {IUniswapV2Pair} from "v2-core/contracts/interfaces/IUniswapV2Pair.sol";
import {UniswapV2Library} from "./libraries/UniswapV2Library.sol";
import {SwapHop} from "./base/OnchainRouterStructs.sol";
import {OnchainRouterImmutables} from "./base/OnchainRouterImmutables.sol";

abstract contract V2Quoter is OnchainRouterImmutables {
    function v2QuoteExactIn(SwapHop memory swap) internal view returns (uint256 amountOut) {
        (uint256 reserveIn, uint256 reserveOut) = getReserves(swap);

        amountOut = UniswapV2Library.getAmountOut(swap.amountSpecified, reserveIn, reserveOut);
    }

    function v2QuoteExactOut(SwapHop memory swap) internal view returns (uint256 amountIn) {
        (uint256 reserveIn, uint256 reserveOut) = getReserves(swap);

        amountIn = UniswapV2Library.getAmountIn(swap.amountSpecified, reserveIn, reserveOut);
    }

    function getReserves(SwapHop memory swap) internal view returns (uint256 reserveIn, uint256 reserveOut) {
        (address token0,) = UniswapV2Library.sortTokens(swap.pool.tokenIn, swap.pool.tokenOut);
        (reserveIn, reserveOut,) = IUniswapV2Pair(swap.pool.pool).getReserves();

        // we need to reverse the tokens
        if (token0 != swap.pool.tokenIn) {
            (reserveIn, reserveOut) = (reserveOut, reserveIn);
        }
    }
}
