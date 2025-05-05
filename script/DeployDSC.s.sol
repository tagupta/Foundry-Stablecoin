// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";

contract DeployDSC is Script {
    function run() external {
        // List of tokenAddresses
        // List of priceFeedAddresses for the corresponding tokens
        // use helper config script to get the constructor arguments accordingly
    }
}
