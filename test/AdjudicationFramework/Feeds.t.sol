pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {Feeds} from "../../contracts/AdjudicationFramework/Push/Feeds.sol";
import {ForkableRealityETH_ERC20} from "../../contracts/ForkableRealityETH_ERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FeedsTest is Test {
    Feeds public feeds;
    address[] public initialArbitrators;

    address public arbitrator1 = address(0x111);
    address public arbitrator2 = address(0x222);
    address public token = address(0xAAA);
    address public realitioMock = address(0x123);
    address public l2Arbitrator = address(0x456);

    function setUp() public {
        // Setup with initial arbitrators
        initialArbitrators = new address[](2);
        initialArbitrators[0] = arbitrator1;
        initialArbitrators[1] = arbitrator2;

        ForkableRealityETH_ERC20 l1RealityEth = new ForkableRealityETH_ERC20();
        l1RealityEth.init(IERC20(address(0x234)), address(0), bytes32(0));

        feeds = new Feeds(address(l1RealityEth), l2Arbitrator, initialArbitrators);
    }

    function testProvideInput() public {
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        tokens[0] = token;
        prices[0] = 100;

        // Arbitrator provides input
        vm.prank(arbitrator1);
        feeds.provideInput(tokens, prices);

        // Check if the input is stored correctly
        (uint256 inputPrice, ) = feeds.arbitratorInputs(token, arbitrator1, 0);
        assertEq(inputPrice, prices[0]);
    }

    function testGetPrice() public {
        address[] memory tokens = new address[](1);
        uint256[] memory prices = new uint256[](1);
        tokens[0] = token;
        prices[0] = 200;

        // Arbitrator provides input
        vm.prank(arbitrator1);
        feeds.provideInput(tokens, prices);

        // Check if the price is retrieved correctly
        uint256 retrievedPrice = feeds.getPrice(token);
        assertEq(retrievedPrice, prices[0]);
    }

    function testCalculateAverage() public {
        address[] memory tokens = new address[](1);
        uint256[] memory prices1 = new uint256[](1);
        uint256[] memory prices2 = new uint256[](1);
        tokens[0] = token;
        prices1[0] = 300;
        prices2[0] = 400;

        // Two arbitrators provide input
        vm.prank(arbitrator1);
        feeds.provideInput(tokens, prices1);
        vm.prank(arbitrator2);
        feeds.provideInput(tokens, prices2);

        // Check if the average is calculated correctly
        uint256 averagePrice = feeds.getPriceConsideringDelay(token, 0);
        assertEq(averagePrice, (prices1[0] + prices2[0]) / 2);
    }

    // Additional tests can include:
    // - Testing `getPriceConsideringDelay` with a delay
    // - Testing invalid inputs or actions by non-arbitrators
    // - Testing edge cases like providing inputs for non-existing tokens
    // - Testing inherited functionalities from `MinimalAdjudicationFramework`
}
