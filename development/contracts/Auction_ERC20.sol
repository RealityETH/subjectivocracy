// SPDX-License-Identifier: GPL-3.0-only

/*
There's a gas token on L2.
This is bridged to an ERC20 on L1, called ForkManager.

After the fork, there will be 2 new tokens, and people with balances on the original token will be able to migrate them to the 2 new tokens.
For 1 week before the fork, there will be an incentivized auction where people can bid whatever they think is the correct valuation of the 2 tokens.
They will then be paid out in one or the other of the tokens, at the rate they bid or better.
eg if you say the value of A:B splits 80:20, you will receive at least either 5 of B or 1.25 of A.
*/

pragma solidity ^0.8.10;

contract Auction_ERC20 {

    // Each slot represents a bid price for the ratio of A:B, price is 1:1 to 100:1
    uint256 constant MAX_SLOTS = 100;
    uint256 public bidCounter;

    uint256 public bonus;
    uint256 public forkTimestamp;
    address public forkmanager;

    struct Bid {
        address owner;
        uint8 bid; // bid price, 1:1 to 100:1 ratio of fork prices
        uint88 amount;
    }

    // maps the bid_price to the cumulative amount of tokens bid at that price
    mapping(uint8 => uint256) public cumulativeBids;
    // maps the bidCounter to the bid
    mapping(uint256 => Bid) public bids;

    bool public isCalculationDone;
    uint8 public finalPrice;
    uint256 public bonusRatio;

    // If you bid exactly on the price at which we setotalBidsed, you can claim whichever your prefer on a first-come-first-serve basis.
    uint256 public tiedYesTokensRemain;
    uint256 public tiedNoTokensRemain;

    event LogBid(
        uint256 bidCounter,
        address payee,
        uint8 bid,
        uint256 value
    );

    event LogChangeBid(
        uint256 bidCounter,
        address payee,
        uint8 oldBid,
        uint8 newBid,
        uint256 value
    );

    modifier beforeFork() {
        require(block.timestamp < forkTimestamp, "must be before fork");
        _;
    }

    modifier onlyForkManager() {
        require(msg.sender == forkmanager, "Call via the forkmanager");
        _;
    }

    modifier afterForkBeforeCalculation() {
        require(block.timestamp >= forkTimestamp, "must be after fork");
        require(!isCalculationDone, "price calculation already done");
        _;
    }

    modifier afterForkAfterCalculation() {
        require(isCalculationDone, "must be after price calculation");
        _;
    }

    // ForkManager should call this on deployment and credit this contract with the bonus amount
    // Todo: maybe this should be a constructor?
    function init(uint256 _bonus, uint256 _forkTimestamp) 
    external {
        require(forkmanager == address(0), "Already initialized");
        forkmanager = msg.sender;
        bonus = _bonus;
        forkTimestamp = _forkTimestamp;
    }

    // ForkManager should lock the tokens before calling this
    function bid(address owner, uint8 _bid, uint88 _amount) 
        beforeFork
    external
    {
        require(_bid <= MAX_SLOTS);
        require(owner != address(0), "Owner not set");

        bidCounter = bidCounter + 1;
        bids[bidCounter] = Bid(owner, _bid, _amount);
        cumulativeBids[_bid] = cumulativeBids[_bid] + _amount;
        emit LogBid(bidCounter, owner, _bid, _amount);
    }

    function changeBid(uint256 _bidCounter, uint8 newBid)
        beforeFork 
    public
    {
        require(newBid <= MAX_SLOTS, "bid higher than MAX_SLOTS");
        address owner = bids[_bidCounter].owner;
        require(owner == msg.sender, "You can only change your own bid");
        uint256 value = bids[_bidCounter].amount;
        uint8 oldBid = bids[_bidCounter].bid;
        bids[bidCounter].bid = newBid;
        cumulativeBids[oldBid] = cumulativeBids[oldBid] - value;
        cumulativeBids[newBid] = cumulativeBids[newBid] + value;
        emit LogChangeBid(bidCounter, owner, oldBid, newBid, value);
    }

    function getTotalBids() 
    view 
    public
    returns (uint256 total)
    {
        for(uint8 i=0; i<=MAX_SLOTS; i++) {
            total = total + cumulativeBids[i];
        }
    }

    function calculatePrice() public
        afterForkBeforeCalculation
    {
        uint256 totalBids = getTotalBids();

        // eg bonus is 100, total is 2000, you get an extra 1/20
        bonusRatio = totalBids / bonus; 
        uint256 sumBids = 0;

        /* 
        Example of price calculation with 200 tokens
        10/90: 10 - cumulative 10, multipler 100/10=10,  uses 100 tokens
        20/80: 10 - cumulative 20, multipler 100/20= 5,  uses 100 tokens
        30/70: 50 - cumulative 70, multipler 100/30=3.3, uses 233 tokens, done
        60/40: 20 
        80/20: 10
        */

        sumBids = cumulativeBids[0];
        for(uint8 i=1; i<=MAX_SLOTS; i++) {
            sumBids = sumBids + cumulativeBids[i];
            uint256 tokensNeeded = (sumBids * MAX_SLOTS / i);
            if ( tokensNeeded >= totalBids ) {
                finalPrice = i;
                isCalculationDone = true;

                /*
                eg we split 60/40 but then the 60 side had 50 tokens, satisfying them all required 210 tokens and there are only 200
                If that happens, assign the excess (10) to the no side and let people claim from whichever side they prefer until there are none left
                */

                uint256 excess = tokensNeeded - totalBids;
                uint256 tokensNeededForThisBidPrice = (cumulativeBids[i] * MAX_SLOTS / i);

                tiedNoTokensRemain = excess;
                tiedYesTokensRemain = tokensNeededForThisBidPrice - excess;
                
                break;
            }
        }
    }

    // todo: deal with the case where the price is 50% and both are winners?
    // maybe a function called: IsMajorityWinner() might more appropriated
    function winner() 
        afterForkAfterCalculation
    external view returns (bool) {
        return (finalPrice * 2 > MAX_SLOTS);
    }

    // Call settleAuction(bid, yesOrNo) against the ForkManager
    // This will read the amount that needs to be paid out, clear it so it isn't paid twice, and mint the tokens in the appropriate token.
    // Usually this would be called by whoever made the bid, but anyone is allowed to call it.
    // There's usually only one option for yesOrNo that won't revert, unless you bid exactly at the setotalBidsement price in which case you may be able to choose.
    function clearAndReturnPayout(uint256 _bidCounter, bool yesOrNo) public
        onlyForkManager
        afterForkAfterCalculation
    returns (address, uint256)
    {
        require(bids[_bidCounter].owner != address(0), "Bid not found");
        uint256 bidAmount = bids[_bidCounter].bid;
        uint256 due;
        address payee = bids[_bidCounter].owner;

        if (yesOrNo) {
            due = bidAmount * MAX_SLOTS / finalPrice;
        } else {
            due = bidAmount * MAX_SLOTS / (MAX_SLOTS - finalPrice);
        }

        if (bidAmount == finalPrice) {
            // If it's a tie, we can only allocate as much as remains available.

            uint256 willPay = due;
            if (yesOrNo && due > tiedYesTokensRemain) {
                willPay = tiedYesTokensRemain;
            } else if (!yesOrNo && due > tiedNoTokensRemain) {
                willPay = tiedNoTokensRemain;
            }
            require(willPay > 0, "No tokens to claim");
            if (willPay < due) {
                // Reduce the remaining bid amount by the proportion of the amount we were unable to fill on the requested side
                bids[_bidCounter].amount = uint88(bidAmount - (bidAmount * willPay / due));
            } else {
                delete(bids[_bidCounter]);
            }

            if (yesOrNo) {
                tiedYesTokensRemain = tiedYesTokensRemain - willPay;
            } else {
                tiedNoTokensRemain = tiedNoTokensRemain - willPay;
            }

            due = willPay;

        } else {
            require( (bidAmount > finalPrice) == yesOrNo, "You can only get yes if you bid same or higher, no same or lower");
            delete(bids[_bidCounter]);
        }

        due = due + (due / bonusRatio);
        return (payee, due);
    }

}
