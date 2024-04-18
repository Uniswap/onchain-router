// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

struct QuoteParams {
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
    uint256 amountIn;
}

struct Route {
    Path[] path;
    uint256 amountIn;
    uint256 amountOut;
}
