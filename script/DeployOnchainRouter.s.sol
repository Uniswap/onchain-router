// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.7.6;

import {Script, console2} from "forge-std/Script.sol";
import {OnchainRouter} from "../src/OnchainRouter.sol";

contract DeployOnchainRouter is Script {
    address constant v2Factory = 0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address constant v3Factory = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address constant weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;

    function setUp() public {}

    function run() public {
        vm.startBroadcast();
        OnchainRouter router = new OnchainRouter(v2Factory, v3Factory, weth);
        console2.log("OnchainRouter deployed at", address(router));
    }
}
