// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";

contract MockAggregator is AggregatorV3Interface {
    uint80 private _roundId;
    int256 private _answer;
    uint256 private _startedAt;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    uint8 private _decimals;

    function setLatestRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        _roundId = roundId;
        _answer = answer;
        _startedAt = startedAt;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function setDecimals(uint8 d) external {
        _decimals = d;
    }

    function latestRoundData() external view returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }
}

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    MockAggregator public primaryFeed;
    MockAggregator public secondaryFeed;
    address public owner = address(0x1);
    uint256 public constant MAX_STALENESS = 3600; // 1 hour

    function setUp() public {
        primaryFeed = new MockAggregator();
        secondaryFeed = new MockAggregator();
        vm.prank(owner);
        oracle = new PriceOracle(address(primaryFeed));

        // Set up primary feed with valid data
        primaryFeed.setDecimals(8);
        primaryFeed.setLatestRoundData(
            1,          // roundId
            2000e8,     // answer (2000 USD)
            block.timestamp - 100,  // startedAt
            block.timestamp - 100,  // updatedAt (within staleness)
            1           // answeredInRound (complete)
        );
    }

    function test_ValidPrice() public {
        int256 price = oracle.getLatestPrice();
        assertEq(price, 2000e8);
    }

    function test_StalePriceUsesFallback() public {
        // Make primary feed stale
        primaryFeed.setLatestRoundData(
            1,
            2000e8,
            block.timestamp - MAX_STALENESS - 100,
            block.timestamp - MAX_STALENESS - 100,
            1
        );

        // Set up fallback with valid data
        vm.prank(owner);
        oracle.setFallbackOracle(address(secondaryFeed));
        secondaryFeed.setLatestRoundData(
            2,
            1995e8,
            block.timestamp - 50,
            block.timestamp - 50,
            2
        );

        // Should return fallback price
        int256 price = oracle.getLatestPrice();
        assertEq(price, 1995e8);
    }

    function test_BothOraclesStaleReverts() public {
        // Make primary feed stale
        primaryFeed.setLatestRoundData(
            1,
            2000e8,
            block.timestamp - MAX_STALENESS - 100,
            block.timestamp - MAX_STALENESS - 100,
            1
        );

        // Set up fallback with stale data too
        vm.prank(owner);
        oracle.setFallbackOracle(address(secondaryFeed));
        secondaryFeed.setLatestRoundData(
            2,
            1995e8,
            block.timestamp - MAX_STALENESS - 200,
            block.timestamp - MAX_STALENESS - 200,
            2
        );

        // Should revert when both oracles are stale
        vm.expectRevert("Both oracles stale");
        oracle.getLatestPrice();
    }

    function test_NegativePriceReverts() public {
        primaryFeed.setLatestRoundData(
            1,
            -100,       // negative price
            block.timestamp - 100,
            block.timestamp - 100,
            1
        );

        vm.expectRevert("Invalid price");
        oracle.getLatestPrice();
    }

    function test_ZeroPriceReverts() public {
        primaryFeed.setLatestRoundData(
            1,
            0,          // zero price
            block.timestamp - 100,
            block.timestamp - 100,
            1
        );

        vm.expectRevert("Invalid price");
        oracle.getLatestPrice();
    }

    function test_IncompleteRoundRejected() public {
        primaryFeed.setLatestRoundData(
            2,          // roundId = 2
            2000e8,
            block.timestamp - 100,
            block.timestamp - 100,
            1           // answeredInRound = 1 (incomplete)
        );

        vm.expectRevert("Invalid price");
        oracle.getLatestPrice();
    }

    function test_StalePriceEvent() public {
        // Setup fallback
        vm.prank(owner);
        oracle.setFallbackOracle(address(secondaryFeed));
        secondaryFeed.setLatestRoundData(
            2,
            1995e8,
            block.timestamp - 50,
            block.timestamp - 50,
            2
        );

        // Make primary stale
        primaryFeed.setLatestRoundData(
            1,
            2000e8,
            block.timestamp - MAX_STALENESS - 100,
            block.timestamp - MAX_STALENESS - 100,
            1
        );

        // StalePrice event should be emitted
        vm.expectEmit(true, true, false, true);
        emit StalePrice(address(primaryFeed), block.timestamp - MAX_STALENESS - 100, address(secondaryFeed));

        oracle.getLatestPrice();
    }

    function test_ConfigurableMaxStaleness() public {
        vm.prank(owner);
        oracle.setMaxStaleness(7200); // 2 hours

        // Price that was 1.5 hours old should now be valid
        primaryFeed.setLatestRoundData(
            1,
            2000e8,
            block.timestamp - 5400,  // 1.5 hours ago
            block.timestamp - 5400,
            1
        );

        int256 price = oracle.getLatestPrice();
        assertEq(price, 2000e8);
    }
}
