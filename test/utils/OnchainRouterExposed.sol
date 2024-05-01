// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {OnchainRouter} from "../../src/OnchainRouter.sol";
import {SwapHop, SwapParams, Quote, Pool} from "../../src/base/OnchainRouterStructs.sol";

contract OnchainRouterExposed is OnchainRouter {
    constructor(address _v2Factory, address _v3Factory, address _weth) OnchainRouter(_v2Factory, _v3Factory, _weth) {}

    /// @notice finds all routes from input to intermediate and from intermediate to output
    /// @dev returns the best route
    function externalRouteExactInputMulti(SwapParams memory params, address intermediate)
        public
        view
        returns (Quote memory bestQuote)
    {
        bestQuote = routeExactInputMulti(params, intermediate);
    }

    /// @notice finds all routes from output to intermediate and from intermediate to input
    /// @dev returns the best route
    function externalRouteExactOutputMulti(SwapParams memory params, address intermediate)
        public
        view
        returns (Quote memory bestQuote)
    {
        bestQuote = routeExactOutputMulti(params, intermediate);
    }

    /// @dev finds and quotes all single pools for a given single hop
    /// @dev and returns the pool with the best quote
    function externalRouteExactInputSingle(SwapParams memory params) public view returns (Quote memory bestQuote) {
        bestQuote = routeExactInputSingle(params);
    }

    /// @dev finds and quotes all single pools for a given single hop
    /// @dev and returns the pool with the best quote
    function externalRouteExactOutputSingle(SwapParams memory params) public view returns (Quote memory bestQuote) {
        bestQuote = routeExactOutputSingle(params);
    }
}
