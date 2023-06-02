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

    uint256 constant MAX_SLOTS = 100;
    uint256 public bid_id;

    uint256 bonus;
    uint256 fork_ts;

    address forkmanager;

    struct Bid {
        uint256 value;
        address owner;
        uint8 bid;
        bool yes_paid; // _paid flags are only used for the tied bid which needs to pay out both sides
        bool no_paid;
    }

    mapping(uint8 => uint256) public cumulative_bids;
    mapping(uint256 => Bid) public bids;

    bool public is_calculation_done;
    uint8 public final_price;
    uint256 public bonus_ratio;

    uint256 public tied_tokens;
    uint256 public tied_yes_tokens;

    event LogBid(
        uint256 bid_id,
        address payee,
        uint8 bid,
        uint256 value
    );

    event LogChangeBid(
        uint256 bid_id,
        address payee,
        uint8 old_bid,
        uint8 new_bid,
        uint256 value
    );

    modifier beforeFork() {
        require(block.timestamp < fork_ts, "must be before fork");
        _;
    }

    modifier onlyForkManager() {
        require(msg.sender == forkmanager, "Call via the forkmanager");
        _;
    }

    modifier afterForkBeforeCalculation() {
        require(block.timestamp >= fork_ts, "must be after fork");
        require(!is_calculation_done, "price calculation already done");
        _;
    }

    modifier afterForkAfterCalculation() {
        require(is_calculation_done, "must be after price calculation");
        _;
    }

    // ForkManager should call this on deployment and credit this contract with the bonus amount
    function init(uint256 _bonus, uint256 _fork_ts) 
    external {
        require(forkmanager == address(0), "Already initialized");
        forkmanager = msg.sender;
        bonus = _bonus;
        fork_ts = _fork_ts;
    }

    // ForkManager should lock the tokens before calling this
    function bid(address owner, uint8 _bid, uint256 _amount) 
        onlyForkManager
        beforeFork
    external
    {

        require(_bid <= MAX_SLOTS);
        require(owner != address(0), "Owner not set");

        bid_id = bid_id + 1;
        bids[bid_id] = Bid(_amount, owner, _bid, false, false);
        emit LogBid(bid_id, owner, _bid, _amount);
        cumulative_bids[_bid] = cumulative_bids[_bid] + _amount;
    }

    function changeBid(uint256 _bid_id, uint8 new_bid)
        beforeFork 
    public
    {
        require(new_bid <= MAX_SLOTS, "bid higher than MAX_SLOTS");
        address owner = bids[_bid_id].owner;
        require(owner == msg.sender, "You can only change your own bid");
        uint256 val = bids[_bid_id].value;
        uint8 old_bid = bids[_bid_id].bid;
        bids[bid_id].bid = new_bid;
        cumulative_bids[old_bid] = cumulative_bids[old_bid] - val;
        cumulative_bids[new_bid] = cumulative_bids[new_bid] + val;
        emit LogChangeBid(bid_id, owner, old_bid, new_bid, val);
    }

    function totalTokens() 
    view 
    public
    returns (uint256)
    {
        uint8 i;
        uint256 ttl = 0;
        for(i=0; i<=MAX_SLOTS; i++) {
            ttl = ttl + cumulative_bids[i];
        }
        return ttl;
    }

    function calculatePrice() public
        afterForkBeforeCalculation
    {
        uint256 ttl = totalTokens();

        // eg bonus is 100, total is 2000, you get an extra 1/20
        bonus_ratio = ttl / bonus; 

        uint256 so_far = 0;
        uint8 i = 0;

        /* 
        Example of price calculation with 200 tokens
        10/90: 10 - cumulative 10, multipler 100/10=10,  uses 100 tokens
        20/80: 10 - cumulative 20, multipler 100/20= 5,  uses 100 tokens
        30/70: 50 - cumulative 70, multipler 100/30=3.3, uses 233 tokens, done
        60/40: 20 
        80/20: 10
        */

        so_far = cumulative_bids[0];
        for(i=1; i<=MAX_SLOTS; i++) {
            so_far = so_far + cumulative_bids[i];
            uint256 tokens_needed = (so_far * MAX_SLOTS / i);
            if ( tokens_needed >= ttl ) {
                final_price = i;
                is_calculation_done = true;

                /*
                eg we split 60/40 but then the 60 side had 50 tokens, satisfying them all required 210 tokens and there are only 200
                If that happens, assign the excess (10) to the no side you are considered to have bid for both sides in proportion
                */

                uint256 excess = tokens_needed - ttl;
                uint256 tokens_needed_for_this_bid = (cumulative_bids[i] * MAX_SLOTS / i);
                tied_yes_tokens = tokens_needed_for_this_bid - excess;
                tied_tokens = cumulative_bids[i];
                
                break;
            }
        }
    }

    function winner() 
        afterForkAfterCalculation
    external view returns (bool) {
        return (final_price * 2 > MAX_SLOTS);
    }

    // Call settleAuction(bid, yes_or_no) against the ForkManager
    // This will read the amount that needs to be paid out, clear it so it isn't paid twice, and mint the tokens in the appropriate token.
    // Usually this would be called by whoever made the bid, but anyone is allowed to call it.
    // There's usually only one option for yes_or_no that won't revert, unless you bid exactly at the settlement price in which case you may be able to choose.
    function clearAndReturnPayout(uint256 _bid_id, bool yes_or_no) public
        onlyForkManager
        afterForkAfterCalculation
    returns (address, uint256)
    {
        require(bids[_bid_id].owner != address(0), "Bid not found");
        uint256 bid_amount = bids[_bid_id].bid;
        uint256 due;
        address payee = bids[_bid_id].owner;

        if (bid_amount == final_price) {

            // If it's a tie, we can only allocate as much as remains available.

            if (yes_or_no && bids[_bid_id].yes_paid || !yes_or_no && bids[_bid_id].no_paid) {
                revert("already paid out");
            }

            // Reduce the remaining bid amount by the proportion of the amount we were unable to fill on the requested side
            if (yes_or_no) {
                bid_amount = tied_yes_tokens * bid_amount / tied_tokens;
            } else {
                bid_amount = (tied_tokens - tied_yes_tokens) * bid_amount / tied_tokens;
            }

            // If we already paid the other side, we can delete
            // Otherwise mark that we paid the side we did
            if (bids[_bid_id].yes_paid || bids[_bid_id].no_paid) {
                delete(bids[_bid_id]);
            } else {
                if (yes_or_no) {
                    bids[_bid_id].yes_paid = true;
                } else {
                    bids[_bid_id].no_paid = true;
                }
            }

        } else {
            require( (bid_amount > final_price) == yes_or_no, "You can only get yes if you bid same or higher, no same or lower");
            delete(bids[_bid_id]);
        }

        if (yes_or_no) {
            due = bid_amount * MAX_SLOTS / final_price;
        } else {
            due = bid_amount * MAX_SLOTS / (MAX_SLOTS - final_price);
        }

        due = due + (due / bonus_ratio);
        return (payee, due);
    }

}
