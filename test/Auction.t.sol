pragma solidity ^0.8.17;
import {Test} from "forge-std/Test.sol";
import {Auction_ERC20} from "../development/contracts/Auction_ERC20.sol";

import {ForkonomicToken} from "../development/contracts/ForkonomicToken.sol";

contract AuctionTest is Test {

    Auction_ERC20 public auc;
    uint256 internal startTs;
    uint256 internal constant FORK_PERIOD = 86400;

    // This would normally be a ForkingManager contract but we'll simulate it with a regular address
    address internal forkManager = address(0xabab01);

    address internal minter = address(0x789);
    address internal bidder1 = address(0xbabe01);
    address internal bidder2 = address(0xbabe02);

    ForkonomicToken internal tokenMock;
    ForkonomicToken internal newTokenImpl;

    // Test constants
    uint256 internal bidder1Bal = 100000;
    uint256 internal bidder2Bal = 200000;

    function setUp() public {
        skip(1000000);

        vm.startPrank(minter);
        tokenMock = new ForkonomicToken();
        tokenMock.initialize(forkManager, address(0), minter, "F0", "F0");

        tokenMock.mint(bidder1, bidder1Bal);
        tokenMock.mint(bidder2, bidder2Bal);

        newTokenImpl = new ForkonomicToken();

        startTs = uint256(block.timestamp);
        auc = new Auction_ERC20();
        auc.init(address(tokenMock), 98765, startTs + FORK_PERIOD);
    }

    function _enterBids(bool yesOrNo) internal {

        uint256 bid10 = yesOrNo ? 10 : 90;
        uint256 bid40 = yesOrNo ? 40 : 60;
        uint256 bid50 = 50;

        vm.startPrank(bidder1);

        tokenMock.approve(address(auc), 1000);
        auc.bid(bidder1, uint8(bid50), 100);

        vm.startPrank(bidder2);
        tokenMock.approve(address(auc), 333);

        auc.bid(bidder2, uint8(bid10), 126);

        vm.startPrank(bidder1);
        auc.bid(bidder1, uint8(bid50), 10);
        auc.bid(bidder1, uint8(bid40), 20);

    }

    function testAuctionToken() public {
        assertEq(address(auc.token()), address(tokenMock), "should be expected token");
    }

    function testFailUnapprovedBid() public {
        vm.startPrank(bidder1);
        auc.bid(bidder1, 50, 100);
    }

    function testFailCalculatePriceBeforeFork() public {
        auc.calculatePrice();
    }

    function testPriceCalculation() public {

        _enterBids(true);

        vm.warp(startTs + FORK_PERIOD + 1);

        // Do the fork
        // We'll use the current token as the new implementation. Really we should probably get the implementation behind the current token, or a new one.
        vm.startPrank(forkManager);
        tokenMock.createChildren(address(newTokenImpl));


        // Anybody can call this when it's time. We'll use one of the bidders.
        vm.startPrank(bidder2);
        auc.calculatePrice();

        assertEq(true, auc.isCalculationDone(), "should be done");

        // Total is 256
        // 10: 126 - 
        // 40: 20
        // 50: 110
        // Clearing price should be between 40 and 50

        // TODO: This case has no bids at the clearing price.
        // Add some bids at the clearing price and make sure they get split.
        
        uint8 finalPrice = auc.finalPrice();
        assertEq(finalPrice, 42);

        // Make sure everyone is now due at least as many tokens as they requested, and that there are no more tokens claimed than exist

    }

    function testWinnerYes() public {
 
        _enterBids(true);

        vm.warp(startTs + FORK_PERIOD + 1);
        auc.calculatePrice();

        assertEq(auc.winner(), true);

    }

    function testWinnerNo() public {
 
        _enterBids(false);

        vm.warp(startTs + FORK_PERIOD + 1);
        auc.calculatePrice();

        assertEq(auc.winner(), false);

    }

    function testBidding() public {

        uint256 bal = tokenMock.balanceOf(bidder1);
        assertEq(bal, bidder1Bal);

        _enterBids(true);

        uint256 newBal = tokenMock.balanceOf(bidder1);
        assertEq(newBal, bidder1Bal-100-10-20);

        uint256 ttl2 = auc.getTotalBids();
        assertEq(ttl2, 100+126+10+20);

        assertEq(auc.cumulativeBids(50), 100+10);
        assertEq(auc.cumulativeBids(40), 20);

    }

}
