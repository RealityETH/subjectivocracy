pragma solidity ^0.8.17;
import {Test} from "forge-std/Test.sol";
import {Auction_ERC20} from "../development/contracts/Auction_ERC20.sol";

import {IERC20} from "../development/contracts/interfaces/IERC20.sol";
import {ERC20Mint} from "../development/contracts/ERC20Mint.sol";

contract AuctionTest is Test {

    Auction_ERC20 public auc;
    uint256 startTs;
    uint256 constant forkPeriod = 86400;

    address minter = address(0x789);
    address bidder1 = address(0xbabe01);
    address bidder2 = address(0xbabe02);

    ERC20Mint tokenMock;

    function setUp() public {
        skip(1000000);

        vm.prank(minter);
        tokenMock = new ERC20Mint();
        tokenMock.mint(bidder1, 100000);
        tokenMock.mint(bidder2, 200000);

        startTs = uint256(block.timestamp);
        auc = new Auction_ERC20();
        auc.init(address(tokenMock), 100000, startTs + forkPeriod);
    }

    function testAuctionToken() public {
        assertEq(address(auc.token()), address(tokenMock), "should be expected token");
    }

    function testFail_UnapprovedBid() public {
        vm.startPrank(bidder1);
        auc.bid(bidder1, 50, 100);
    }

    function testBidding() public {

        vm.startPrank(bidder1);

        uint256 bal = tokenMock.balanceOf(bidder1);
        assertEq(bal, 100000);

        tokenMock.approve(address(auc), 1000);
        auc.bid(bidder1, 50, 100);

        uint256 newBal = tokenMock.balanceOf(bidder1);
        assertEq(newBal, 100000-100);

        uint256 ttl = auc.getTotalBids();
        assertEq(ttl, 100);

        vm.startPrank(bidder2);
        tokenMock.approve(address(auc), 333);
        auc.bid(bidder2, 10, 126);

        vm.startPrank(bidder1);
        auc.bid(bidder1, 50, 10);
        auc.bid(bidder1, 40, 20);

        uint256 newBal2 = tokenMock.balanceOf(bidder1);
        assertEq(newBal2, 100000-100-10-20);

        uint256 ttl2 = auc.getTotalBids();
        assertEq(ttl2, 100+126+10+20);

        assertEq(auc.cumulativeBids(50), 100+10);
        assertEq(auc.cumulativeBids(40), 20);

    }

}
