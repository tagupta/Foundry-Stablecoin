// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Script} from "forge-std/Script.sol";
import {MockV3Aggregator} from "@chainlink/contracts/src/v0.8/shared/mocks/MockV3Aggregator.sol";
import {ERC20Mock} from "test/mocks/ERC20Mock.sol";

contract HelperConfig is Script {
    enum Token {
        ETH,
        BTC
    }

    struct NetworkConfig {
        mapping(Token => address) tokenAddresses;
        mapping(Token => address) priceFeeds;
        uint256 deployerKey;
    }

    NetworkConfig private activeNetworkConfig;
    uint8 public constant DECIMALS = 8;
    uint8 public constant TOTAL_TOKENS = 2;
    int256 public constant INITIAL_PRICE_ETH = 2000e8;
    int256 public constant INITIAL_PRICE_BTC = 1000e8;
    uint256 public constant SEPOLIA_CHAIN_ID = 11155111;
    uint256 public constant MAINNET_CHAIN_ID = 1;
    uint256 public DEFAULT_ANVIL_PRIVATE_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

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
        returns (address[] memory tokens, address[] memory feeds, uint256 deployerKey)
    {
        tokens = new address[](2);
        feeds = new address[](2);
        tokens[0] = activeNetworkConfig.tokenAddresses[Token.ETH];
        tokens[1] = activeNetworkConfig.tokenAddresses[Token.BTC];
        feeds[0] = activeNetworkConfig.priceFeeds[Token.ETH];
        feeds[1] = activeNetworkConfig.priceFeeds[Token.BTC];
        deployerKey = activeNetworkConfig.deployerKey;
    }

    function _setupSepoliaConfig() internal {
        activeNetworkConfig.tokenAddresses[Token.ETH] = 0xdd13E55209Fd76AfE204dBda4007C227904f0a81;
        //0x7b79995e5f793A07Bc00c21412e50Ecae098E7f9;
        activeNetworkConfig.tokenAddresses[Token.BTC] = 0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063;
        //0x29f2D40B0605204364af54EC677bD022dA425d03;

        activeNetworkConfig.priceFeeds[Token.ETH] = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
        activeNetworkConfig.priceFeeds[Token.BTC] = 0x1b44F3514812d835EB1BDB0acB33d3fA3351Ee43;
        activeNetworkConfig.deployerKey = vm.envUint("PRIVATE_KEY");
    }

    function _setupMainnetConfig() internal {
        activeNetworkConfig.tokenAddresses[Token.ETH] = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        activeNetworkConfig.tokenAddresses[Token.BTC] = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;

        activeNetworkConfig.priceFeeds[Token.ETH] = 0x5147eA642CAEF7BD9c1265AadcA78f997AbB9649;
        activeNetworkConfig.priceFeeds[Token.BTC] = 0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c;
        activeNetworkConfig.deployerKey = vm.envUint("PRIVATE_KEY_MAIN");
    }

    function _setupAnvilConfig() internal {
        if (activeNetworkConfig.priceFeeds[Token.ETH] != address(0)) return;

        vm.startBroadcast();

        MockV3Aggregator ethUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_ETH);
        ERC20Mock weth = new ERC20Mock("Wrapped Ether", "WETH", msg.sender, 1000e8);

        MockV3Aggregator btcUsdPriceFeed = new MockV3Aggregator(DECIMALS, INITIAL_PRICE_BTC);
        ERC20Mock wbtc = new ERC20Mock("Wrapped Bitcoin", "WBTC", msg.sender, 1000e8);

        vm.stopBroadcast();

        activeNetworkConfig.tokenAddresses[Token.ETH] = address(weth);
        activeNetworkConfig.tokenAddresses[Token.BTC] = address(wbtc);

        activeNetworkConfig.priceFeeds[Token.ETH] = address(ethUsdPriceFeed);
        activeNetworkConfig.priceFeeds[Token.BTC] = address(btcUsdPriceFeed);
        activeNetworkConfig.deployerKey = DEFAULT_ANVIL_PRIVATE_KEY;
    }
}
