// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface AggregatorV3Interface {
    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    );
    function decimals() external view returns (uint8);
}

contract PriceOracle {
    AggregatorV3Interface public primaryFeed;
    AggregatorV3Interface public secondaryFeed;
    address public owner;
    uint256 public MAX_STALENESS = 3600;

    event PriceQueried(int256 price, uint256 timestamp);
    event StalePrice(address indexed primaryOracle, uint256 lastUpdateTimestamp, address indexed fallbackOracle);
    event FallbackOracleUpdated(address indexed oldFallback, address indexed newFallback);

    constructor(address _primaryFeed) {
        primaryFeed = AggregatorV3Interface(_primaryFeed);
        owner = msg.sender;
    }

    function getLatestPrice() external view returns (int256) {
        (int256 price, bool isStale, bool isValid) = _queryFeed(primaryFeed);

        if (isStale && address(secondaryFeed) != address(0)) {
            (int256 fallbackPrice, bool fallbackStale, bool fallbackValid) = _queryFeed(secondaryFeed);
            if (!fallbackStale && fallbackValid) {
                return fallbackPrice;
            }
            revert("Both oracles stale");
        }

        require(isValid, "Invalid price");
        return price;
    }

    function _queryFeed(AggregatorV3Interface feed) internal view returns (int256 price, bool isStale, bool isValid) {
        (
            uint80 roundId,
            int256 _price,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Validate price is positive
        if (_price <= 0) {
            return (0, false, false);
        }

        // Validate round completeness
        if (answeredInRound < roundId) {
            return (0, false, false);
        }

        // Check staleness
        if (block.timestamp - updatedAt > MAX_STALENESS) {
            return (0, true, true);
        }

        return (_price, false, true);
    }

    function getDecimals() external view returns (uint8) {
        return primaryFeed.decimals();
    }

    function setMaxStaleness(uint256 _maxStaleness) external {
        require(msg.sender == owner, "Not owner");
        MAX_STALENESS = _maxStaleness;
    }

    function setFallbackOracle(address _fallbackOracle) external {
        require(msg.sender == owner, "Not owner");
        emit FallbackOracleUpdated(address(secondaryFeed), _fallbackOracle);
        secondaryFeed = AggregatorV3Interface(_fallbackOracle);
    }
}
