// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

contract Auction {

    uint256 constant MAX_SLOTS = 100;
    uint256 public bid_id;

    uint256 bonus;

    address forkmanager;

    struct Bid {
        address owner;
        uint8 bid;
        uint256 value;
    }

    mapping(uint8 => uint256) public cumulative_bids;
    mapping(uint256 => Bid) public bids;

    bool is_fork_done;
    bool is_calculation_done;
    uint8 final_price;

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
        require(!is_fork_done);
        _;
    }

    modifier afterForkBeforeCalculation() {
        require(is_fork_done);
        require(!is_calculation_done);
        _;
    }

    modifier afterForkAfterCalculation() {
        require(is_fork_done);
        require(is_calculation_done);
        _;
    }

    constructor() {
        forkmanager = msg.sender;
    }

    function markForkDone() 
    public
    {
        require(msg.sender == forkmanager);
        is_fork_done = true; 
    }

    function addBonus() 
        beforeFork
    external
    payable
    {
        require(msg.sender == forkmanager);
        bonus = msg.value;
    }


    function bid(address owner, uint8 _bid) 
        beforeFork
    public
    payable
    {
        require(_bid <= MAX_SLOTS);
        require(owner != address(0), "Owner not set");
        bid_id = bid_id + 1;
        bids[bid_id] = Bid(owner, _bid, msg.value);
        emit LogBid(bid_id, owner, _bid, msg.value);
        cumulative_bids[_bid] = cumulative_bids[_bid] + msg.value;
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

}
