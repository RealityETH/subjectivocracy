pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {AdjudicationFrameworkFeeds} from "../../contracts/AdjudicationFramework/Push/AdjudicationFrameworkFeeds.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {RealityETH_v3_0} from "../../contracts/lib/reality-eth/RealityETH-3.0.sol";

contract FeedsTest is Test {
    AdjudicationFrameworkFeeds public feeds;
    address[] public initialArbitrators;

    address public arbitrator1 = address(0x111);
    address public arbitrator2 = address(0x222);
    address public token = address(0xAAA);
    address public realitioMock = address(0x123);
    address public l2Arbitrator = address(0x456);

    function setUp() public {
        // Setup with initial arbitrators
        initialArbitrators = new address[](1);
        initialArbitrators[0] = arbitrator1;

        RealityETH_v3_0 l2RealityEth = new RealityETH_v3_0();

        feeds = new AdjudicationFrameworkFeeds(
            address(l2RealityEth),
            l2Arbitrator,
            initialArbitrators
        );
    }

    function testGetOracleContract() public {
        assertEq(feeds.getOracleContract(), arbitrator1);
    }
}
