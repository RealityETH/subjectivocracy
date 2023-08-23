pragma solidity ^0.8.17;
import {Test} from "forge-std/Test.sol";
import {Auction_ERC20} from "../development/contracts/Auction_ERC20.sol";

import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ForkonomicToken} from "../development/contracts/ForkonomicToken.sol";

contract AuctionTest is Test {

    Auction_ERC20 public auc;
    uint256 internal startTs;
    uint256 internal constant FORK_PERIOD = 86400;

    // This would normally be a ForkingManager contract but we'll simulate it with a regular address
    address internal forkManager = address(0xabab01);

    address internal deployer = address(0x890);

    address internal minter = address(0x789);
    address internal bidder1 = address(0xbabe01);
    address internal bidder2 = address(0xbabe02);

    ForkonomicToken internal tokenMock;

    //address internal newToken;
    ForkonomicToken internal newTokenImpl;

    // Test constants
    uint256 internal bidder1Bal = 100000;
    uint256 internal bidder2Bal = 200000;

    function setUp() public {
        skip(1000000);

        vm.startPrank(minter);
        ForkonomicToken tokenMockImpl = new ForkonomicToken();
        address tokenMockAddr = address(new TransparentUpgradeableProxy(address(tokenMockImpl), deployer, ""));
        tokenMock = ForkonomicToken(tokenMockAddr);
        tokenMock.initialize(forkManager, address(0), minter, "F0", "F0");

        tokenMock.mint(bidder1, bidder1Bal);
        tokenMock.mint(bidder2, bidder2Bal);

        newTokenImpl = new ForkonomicToken();
        //newToken = address(new TransparentUpgradeableProxy(address(newTokenImpl), minter, ""));

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

    // Does the minimal we need to simulate the fork from the point of view of the auction contract.
    // Forks the token but leaves other stuff alone.
    function _simulateFork() internal {

        vm.warp(startTs + FORK_PERIOD + 1);

        // Do the fork
        // We'll use the current token as the new implementation. Really we should probably get the implementation behind the current token, or a new one.
        vm.startPrank(forkManager);

        address childToken0;
        address childToken1;
        (childToken0, childToken1) = tokenMock.createChildren(address(newTokenImpl));

        // Really the forkManager would be cloned as well
        ForkonomicToken(childToken0).initialize(forkManager, address(tokenMock), minter, "F1", "F1");
        ForkonomicToken(childToken1).initialize(forkManager, address(tokenMock), minter, "F2", "F2");

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

        _simulateFork();
    
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

    function testBalanceSplit() public {

        _enterBids(true);

        uint256 balBefore = tokenMock.balanceOf(address(auc));
        assertEq(balBefore, 256);

        _simulateFork();
    
        auc.calculatePrice();

        assertEq(true, auc.isCalculationDone(), "should be done");

        uint256 balAfter = tokenMock.balanceOf(address(auc));
        assertEq(balAfter, 0);

        address child0 = tokenMock.children(0);
        address childToken0 = tokenMock.children(1);
        
        assertEq(ForkonomicToken(child0).balanceOf(address(auc)), 256);
        assertEq(ForkonomicToken(childToken0).balanceOf(address(auc)), 256);

    }

    function testWinnerYes() public {
 
        _enterBids(true);
        _simulateFork();
    
        auc.calculatePrice();

        assertEq(auc.winner(), true);

    }

    function testWinnerNo() public {
 
        _enterBids(false);
        _simulateFork();

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

    /*
    function testFailPayoutOtherPersonsBid() public {

        _enterBids(false);
        _simulateFork();

        auc.calculatePrice();

        // Bidder 1 has 20 at 40
        vm.startPrank(bidder2);

        auc.payoutBid(1, false); 

    }
    */

    function testFailRepeatedPayouts() public {

        _enterBids(false);
        _simulateFork();

        auc.calculatePrice();

        // Bidder 1 has 20 at 40
        vm.startPrank(bidder1);

        auc.payoutBid(1, false);
        auc.payoutBid(1, false);
    }

    function testPayouts() public {

        _enterBids(false);
        _simulateFork();

        auc.calculatePrice();

        // Bidder 1 has 20 at 40
        vm.startPrank(bidder1);

        // TODO: Check yes and no aren't tangled up

        auc.payoutBid(1, false); // Bids should start at 1
        // Next step: Check bidder1 balance
        
        // Bidder 1 has 110 at 50

        //auc.bid(bidder1, uint8(bid50), 100);
        //auc.bid(bidder2, uint8(bid10), 126);
        //auc.bid(bidder1, uint8(bid50), 10);
        //auc.bid(bidder1, uint8(bid40), 20);

    }

}
