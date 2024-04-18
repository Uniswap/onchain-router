// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

struct SwapParams {
    address tokenIn;
    address tokenOut;
    uint256 amountSpecified;
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
    uint256 amountSpecified;
}

struct Quote {
    Pool[] path;
    uint256 amountIn;
    uint256 amountOut;
}
