// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

struct ExactInputRouteRequestParams {
    address tokenIn;
    address tokenOut;
    uint256 amountIn;
}

struct ExactOutputRouteRequestParams {
    address tokenIn;
    address tokenOut;
    uint256 amountOut;
}

struct Pool {
    address tokenIn;
    address tokenOut;
    uint24 fee;
    address pool;
    bool version;
}

struct SwapHop {
    Pool pool;
    uint256 amount;
    bool exactIn;
}

struct Quote {
    Pool[] path;
    uint256 amountIn;
}
