// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";

contract DeployDSC is Script {
    function run() external returns (DecentralizedStablecoin, DSCEngine) {
        // List of tokenAddresses
        // List of priceFeedAddresses for the corresponding tokens
        // use helper config script to get the constructor arguments accordingly
        vm.startBroadcast();

        vm.stopBroadcast();
    }
}
