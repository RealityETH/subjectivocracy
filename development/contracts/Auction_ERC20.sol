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
        address owner;
        uint8 bid;
        uint256 value;
    }

    mapping(uint8 => uint256) public cumulative_bids;
    mapping(uint256 => Bid) public bids;

    bool is_calculation_done;
    uint8 public final_price;
    uint256 public bonus_ratio;

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
        require(block.timestamp < fork_ts);
        _;
    }

    modifier afterForkBeforeCalculation() {
        require(block.timestamp >= fork_ts);
        require(!is_calculation_done);
        _;
    }

    modifier afterForkAfterCalculation() {
        require(block.timestamp >= fork_ts);
        require(is_calculation_done);
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
        beforeFork
    external
    {
        require(msg.sender == forkmanager, "Call via the forkmanager");

        require(_bid <= MAX_SLOTS);
        require(owner != address(0), "Owner not set");

        bid_id = bid_id + 1;
        bids[bid_id] = Bid(owner, _bid, _amount);
        emit LogBid(bid_id, owner, _bid, _amount);
        cumulative_bids[_bid] = cumulative_bids[_bid] + _amount;
    }

    function changeBid(uint256 _bid_id, uint8 new_bid)
        beforeFork 
    public
    {
        require(new_bid <= MAX_SLOTS);
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
        bonus_ratio = ttl / bonus; // eg bonus is 100, total is 2000, you get an extra 1/20
        uint256 so_far = 0;
        uint8 i = 0;
        for(i=0; i<MAX_SLOTS; i++) {
            so_far = so_far + cumulative_bids[i];
            if ( (so_far * i / MAX_SLOTS) > ttl ) {
                final_price = i; // TODO: Should this be halfway through the last slot?
                return;
            }
        }
    }

    function winner() 
        afterForkAfterCalculation
    external view returns (bool) {
        return (final_price * 2 > MAX_SLOTS);
    }

    // Call settleAuction(bid) against the ForkManager
    // This will read the amount that needs to be paid out, clear it so it isn't paid twice, and mint the tokens in the appropriate token.
    // Usually this would be called by whoever made the bid, but anyone is allowed to call it.
    function clearAndReturnPayout(uint256 _bid_id) public
        afterForkAfterCalculation
    returns (address, bool, uint256)
    {
        require(forkmanager == msg.sender, "Payout should be called against forkmanager");
        require(bids[_bid_id].owner != address(0), "Bid not found");
        uint256 bid_amount = bids[_bid_id].bid;
        uint256 due;
        address payee = bids[_bid_id].owner;
        bool yes_or_no;
        if (bid_amount > final_price) {
            due = bid_amount * MAX_SLOTS / final_price;
            yes_or_no = true;
        } else {
            due = bid_amount * MAX_SLOTS / (MAX_SLOTS - final_price);
            yes_or_no = false;
        }
        due = due + (due / bonus_ratio);
        delete(bids[_bid_id]);
        return (payee, yes_or_no, due);
    }

}
