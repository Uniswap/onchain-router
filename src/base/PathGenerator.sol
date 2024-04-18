// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;
pragma abicoder v2;

import {IUniswapV3Factory} from "v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV2Factory} from "v2-core/contracts/interfaces/IUniswapV2Factory.sol";
import {UniswapV2Library} from "../libraries/UniswapV2Library.sol";
import {Pool} from "./OnchainRouterStructs.sol";
import {OnchainRouterImmutables} from "./OnchainRouterImmutables.sol";

abstract contract PathGenerator is OnchainRouterImmutables {
    uint24[4] currentV3FeeTiers = [uint24(100), uint24(500), uint24(3000), uint24(10000)];

    function generatePaths(address tokenIn, address tokenOut) internal view returns (Pool[] memory paths) {
        Pool[] memory v2Path = generateV2Path(tokenIn, tokenOut);
        Pool[] memory v3Paths = generateV3Paths(tokenIn, tokenOut);

        paths = addPaths(v2Path, v3Paths);
    }

    function getV3Pools(address token0, address token1, uint24[4] memory fees)
        private
        view
        returns (address[] memory pools)
    {
        pools = new address[](fees.length);

        for (uint256 i = 0; i < fees.length; i++) {
            pools[i] = v3Factory.getPool(token0, token1, fees[i]);
        }
    }

    function generateV3Paths(address tokenIn, address tokenOut) private view returns (Pool[] memory paths) {
        uint24[4] memory fees = currentV3FeeTiers;

        uint256 validPaths;
        paths = new Pool[](fees.length);

        (address[] memory pools) = getV3Pools(tokenIn, tokenOut, fees);

        for (uint256 i = 0; i < pools.length; i++) {
            if (pools[i] != address(0)) {
                Pool memory path =
                    Pool({tokenIn: tokenIn, tokenOut: tokenOut, pool: pools[i], fee: fees[i], version: true});
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
            path[0] = Pool({tokenIn: tokenIn, tokenOut: tokenOut, pool: v2Pool, fee: uint24(3000), version: false});
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
