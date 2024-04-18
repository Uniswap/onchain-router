// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {UniswapV2Library} from "../libraries/UniswapV2Library.sol";
import {Pool} from "./OnchainRouterStructs.sol";
import {OnchainRouterImmutables} from "./OnchainRouterImmutables.sol";

abstract contract PathGenerator is OnchainRouterImmutables {
    // default fee tiers to check
    uint24[4] private defaultFeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];
    // currently supported fee tiers
    uint24[] public feeTiers;
    // default V2 fee tier
    uint24 private constant V2_FEE_TIER = 3000;

    constructor(address v3Factory) {
        for (uint256 i = 0; i < defaultFeeTiers.length; i++) {
            uint24 feeTier = defaultFeeTiers[i];
            if (IUniswapV3Factory(v3Factory).feeAmountTickSpacing(feeTier) != 0) {
                feeTiers.push(feeTier);
            }
        }
    }

    /// @notice add the new fee tier to the fee tier list if it exists on the factory
    function addNewFeeTier(uint24 feeTier) public {
        if (v3Factory.feeAmountTickSpacing(feeTier) != 0) {
            feeTiers.push(feeTier);
        }
    }

    function generatePaths(address tokenIn, address tokenOut) internal view returns (Pool[] memory paths) {
        Pool[] memory v2Path = generateV2Path(tokenIn, tokenOut);
        Pool[] memory v3Paths = generateV3Paths(tokenIn, tokenOut);

        paths = addPaths(v2Path, v3Paths);
    }

    function generateV3Paths(address tokenIn, address tokenOut) private view returns (Pool[] memory paths) {
        uint256 validPaths;
        paths = new Pool[](feeTiers.length);

        for (uint256 i = 0; i < feeTiers.length; i++) {
            uint24 feeTier = feeTiers[i];
            (address token0, address token1) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
            address pool = v3Factory.getPool(token0, token1, feeTier);

            if (pool != address(0)) {
                Pool memory path = Pool({tokenIn: tokenIn, tokenOut: tokenOut, pool: pool, fee: feeTier, version: true});
                paths[validPaths] = path;
                validPaths++;
            }
        }
        // set paths length to validPaths
        assembly {
            mstore(paths, validPaths)
        }
    }

    function generateV2Path(address tokenIn, address tokenOut) private view returns (Pool[] memory path) {
        (address token0, address token1) = UniswapV2Library.sortTokens(tokenIn, tokenOut);
        address v2Pool = v2Factory.getPair(token0, token1);

        path = new Pool[](1);
        if (v2Pool != address(0)) {
            path[0] = Pool({tokenIn: tokenIn, tokenOut: tokenOut, pool: v2Pool, fee: V2_FEE_TIER, version: false});
        } else {
            // set paths length to 0
            assembly {
                mstore(path, 0)
            }
        }
    }

    function addPaths(Pool[] memory path1, Pool[] memory path2) private pure returns (Pool[] memory path) {
        uint256 length = path1.length + path2.length;
        path = new Pool[](length);

        for (uint256 i = 0; i < path1.length; i++) {
            path[i] = path1[i];
        }

        for (uint256 i = 0; i < path2.length; i++) {
            path[i + path1.length] = path2[i];
        }
    }
}
