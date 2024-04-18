// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";

abstract contract OnchainRouterImmutables {
    IUniswapV2Factory public immutable v2Factory;
    IUniswapV3Factory public immutable v3Factory;

    constructor(address _v2Factory, address _v3Factory) {
        v2Factory = IUniswapV2Factory(_v2Factory);
        v3Factory = IUniswapV3Factory(_v3Factory);
    }
}
