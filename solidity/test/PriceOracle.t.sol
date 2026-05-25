// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/PriceOracle.sol";

contract MockAggregator is AggregatorV3Interface {
    uint80 private _roundId;
    int256 private _answer;
    uint256 private _updatedAt;
    uint80 private _answeredInRound;
    uint8 private _decimals;

    function setLatestRoundData(uint80 roundId, int256 answer, uint256 updatedAt, uint80 answeredInRound) external {
        _roundId = roundId;
        _answer = answer;
        _updatedAt = updatedAt;
        _answeredInRound = answeredInRound;
    }

    function latestRoundData() external view override returns (uint80, int256, uint256, uint256, uint80) {
        return (_roundId, _answer, 0, _updatedAt, _answeredInRound);
    }

    function decimals() external view override returns (uint8) { return _decimals; }
}

contract PriceOracleTest is Test {
    MockAggregator primary;
    MockAggregator secondary;
    PriceOracle oracle;

    function setUp() public {
        primary = new MockAggregator();
        secondary = new MockAggregator();
        oracle = new PriceOracle(address(primary), address(secondary));
        vm.warp(1000000);
    }

    function test_ValidPrice() public {
        primary.setLatestRoundData(1, 1000e8, block.timestamp - 100, 1);
        (int256 price) = oracle.getLatestPrice();
        assertEq(price, 1000e8);
    }

    function test_StalePriceFallsBack() public {
        primary.setLatestRoundData(1, 1000e8, block.timestamp - 4000, 1);
        secondary.setLatestRoundData(1, 1050e8, block.timestamp - 100, 1);
        (int256 price) = oracle.getLatestPrice();
        assertEq(price, 1050e8);
    }

    function test_BothOraclesStaleReverts() public {
        primary.setLatestRoundData(1, 1000e8, block.timestamp - 4000, 1);
        secondary.setLatestRoundData(1, 1050e8, block.timestamp - 4000, 1);
        vm.expectRevert("Both oracles stale");
        oracle.getLatestPrice();
    }

    function test_NegativePriceReverts() public {
        primary.setLatestRoundData(1, -100, block.timestamp - 100, 1);
        vm.expectRevert("Invalid price");
        oracle.getLatestPrice();
    }

    function test_IncompleteRoundReverts() public {
        primary.setLatestRoundData(5, 1000e8, block.timestamp - 100, 3);
        vm.expectRevert("Incomplete round");
        oracle.getLatestPrice();
    }
}
