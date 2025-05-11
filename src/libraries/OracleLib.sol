// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/**
 * @title Oracle Lib
 * @author Tanu Gupta
 * @notice This library is used to check the chainlink oracle for stale data.
 * If a price is stale, the function will revert and render the DSCEngine Unusable - this is by design.
 * We want DSCEngine to freeze if prices become stale.
 *
 * Bug: If the chainlink newtork explodes and you have a lot of money locked up in the protocol -> SCREWED
 */
library OracleLib {
    error OracleLib__StalePrice();

    uint256 public constant TIME_OUT = 3 hours; //3 * 60 * 60

    function staleCheckLatestRoundData(AggregatorV3Interface priceFeedAddress)
        public
        view
        returns (uint80, int256, uint256, uint256, uint80)
    {
        (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) =
            priceFeedAddress.latestRoundData();
        uint256 secondsSince = block.timestamp - updatedAt;
        if (secondsSince > TIME_OUT) revert OracleLib__StalePrice();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
