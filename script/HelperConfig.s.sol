// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {WETH} from 'test/mocks/MockETH.sol';
import {WBTC} from 'test/mocks/MockBTC.sol';

contract HelperConfig is Script {
    enum Token {
        ETH,
        BTC
    }

    struct NetworkConfig {
        mapping(Token => address) tokenAddresses;
        mapping(Token => address) priceFeeds;
    }

    NetworkConfig private activeNetworkConfig;
    uint8 public constant DECIMALS = 8;
    uint8 public constant TOTAL_TOKENS = 2;
    int256 public constant INITIAL_PRICE_ETH = 2000e8;
    int256 public constant INITIAL_PRICE_BTC = 94480e8;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;

   constructor() {
        if (block.chainid == SEPOLIA_CHAIN_ID) {
            _setupSepoliaConfig();
        } else if (block.chainid == MAINNET_CHAIN_ID) {
            _setupMainnetConfig();
        } else {
            _setupAnvilConfig();
        }
    }

       function getNetworkConfig() 
        external 
        view 
        returns (address[2] memory tokens, address[2] memory feeds) 
    {
        tokens = [
            activeNetworkConfig.tokenAddresses[Token.ETH],
            activeNetworkConfig.tokenAddresses[Token.BTC]
        ];
        feeds = [
            activeNetworkConfig.priceFeeds[Token.ETH],
            activeNetworkConfig.priceFeeds[Token.BTC]
        ];
    }

    function _setupSepoliaConfig() internal {
        activeNetworkConfig.tokenAddresses[Token.ETH] = 0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        activeNetworkConfig.tokenAddresses[Token.BTC] = 0x29f2D40B0605204364af54EC677bD022dA425d03;

        activeNetworkConfig.priceFeeds[Token.ETH] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        activeNetworkConfig.priceFeeds[Token.BTC] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
    }

    function _setupMainnetConfig() internal {
        activeNetworkConfig.tokenAddresses[Token.ETH] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        activeNetworkConfig.tokenAddresses[Token.BTC] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

        activeNetworkConfig.priceFeeds[Token.ETH] = 0x5147eA642CAEF7BD9c1265AadcA78f997AbB9649;
        activeNetworkConfig.priceFeeds[Token.BTC] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
    }

    function _setupAnvilConfig() internal {
        if (
            activeNetworkConfig.priceFeeds[Token.ETH] != address(0)
        ) return;
        vm.startBroadcast();
        MockV3Aggregator aggregatorInteraceEth = new MockV3Aggregator({_decimals: DECIMALS, _initialAnswer: INITIAL_PRICE_ETH});
        MockV3Aggregator aggregatorInteraceBtc = new MockV3Aggregator({_decimals: DECIMALS, _initialAnswer: INITIAL_PRICE_BTC});
        WETH weth = new WETH();
        WBTC wbtc = new WBTC();
        vm.stopBroadcast();
        activeNetworkConfig.tokenAddresses[Token.ETH] = address(weth);
        activeNetworkConfig.tokenAddresses[Token.BTC] = address(wbtc);

        activeNetworkConfig.priceFeeds[Token.ETH] = address(aggregatorInteraceEth);
        activeNetworkConfig.priceFeeds[Token.BTC] = address(aggregatorInteraceBtc);

        
    }
}
