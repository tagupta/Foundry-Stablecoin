// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import {Script} from "forge-std/Script.sol";
import {DecentralizedStablecoin} from "src/DecentralizedStablecoin.sol";
import {DSCEngine} from "src/DSCEngine.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";

contract DeployDSC is Script {
    function run() external returns (DecentralizedStablecoin, DSCEngine, address[] memory, address[] memory) {
        HelperConfig helperConfig = new HelperConfig();

        (address[] memory tokens, address[] memory feeds, uint256 deployerKey) = helperConfig.getNetworkConfig();

        vm.startBroadcast(deployerKey);
        DecentralizedStablecoin dsc = new DecentralizedStablecoin();
        DSCEngine engine = new DSCEngine(tokens, feeds, address(dsc));
        dsc.transferOwnership(address(engine));
        vm.stopBroadcast();

        return (dsc, engine, tokens, feeds);
    }
}
