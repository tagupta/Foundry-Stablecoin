// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";

contract HelperConfig is Script {
    NetworkConfig public networkActiveConfig;

    struct NetworkConfig {
        string tokenName;
        address tokenAddress;
        address priceFeed; //ETH/USD price feed
    }
}
