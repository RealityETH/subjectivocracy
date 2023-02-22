// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import './BalanceHolder.sol';

import './RealityETH_ERC20-3.0.sol';

import './IArbitrator.sol';
import './IAMB.sol';
import './IERC20.sol';

/*
This contract sits between a Reality.eth instance and an Arbitrator.
It manages a whitelist of arbitrators, and makes sure questions can be sent to an arbitrator on the whitelist.
When called on to arbitrate, it pays someone to send out the arbitration job to an arbitrator on the whitelist.
Arbitrators can be disputed on L1.
To Reality.eth it looks like a normal arbitrator, implementing the Arbitrator interface.
To the normal Arbitrator contracts that does its arbitration jobs, it looks like Reality.eth.
*/
contract WhitelistArbitrator is BalanceHolder {

    // From RealityETH_ERC20
    struct Question {
        bytes32 content_hash;
        address arbitrator;
        uint32 opening_ts;
        uint32 timeout;
        uint32 finalize_ts;
        bool is_pending_arbitration;
        uint256 bounty;
        bytes32 best_answer;
        bytes32 history_hash;
        uint256 bond;
        uint256 min_bond;
    }

    mapping(bytes32 => Question) public questions;

    IAMB bridge;
    uint256 constant public ARB_DISPUTE_TIMEOUT = 86400;
    uint256 constant public QUESTION_UNHANDLED_TIMEOUT = 86400;

    uint256 constant public TOKEN_RESERVATION_BIDDING_PERIOD= 86400; // After you make a bid, people have 1 day to outbid you
    uint256 constant public TOKEN_RESERVATION_CLAIM_TIMEOUT = 864000; // After a bid is accepted, you have 9 days to complete it or you can lose your deposit
    uint256 constant public TOKEN_RESERVATION_DEPOSIT = 10; // 1/10, ie 10%

    // The bridge (either on L1 or L2) should switch out real L1 forkmanager address for a special address
    address constant FORK_MANAGER_SPECIAL_ADDRESS = 0x00000000000000000000000000000000f0f0F0F0;

    event LogRequestArbitration(
        bytes32 indexed question_id,
        uint256 fee_paid,
        address requester,
        uint256 remaining
    );

    event LogNotifyOfArbitrationRequest(
        bytes32 indexed question_id,
        address indexed user 
    );

    struct TokenReservation {
        address reserver;
        uint256 num;
        uint256 price;
        uint256 reserved_ts;
    }
    mapping (bytes32 => TokenReservation) public token_reservations;
    uint256 public reserved_tokens;

    // Whitelist of acceptable arbitrators
    mapping (address => bool) public arbitrators;

    // List of arbitrators that are currently being challenged
    mapping (address => bool) public frozen_arbitrators;

    RealityETH_ERC20_v3_0 public realityETH;

    uint256 public dispute_fee;

    struct ArbitrationRequest {
        address arbitrator;
        address payer;
        uint256 bounty;
        bytes32 msg_hash;
        uint256 finalize_ts;
        uint256 last_action_ts;
    }

    mapping (bytes32 => ArbitrationRequest) public question_arbitrations;

    // TODO: Work out how this is implemented in xdai or whatever we use
    modifier l1_forkmanager_only() {
        require(msg.sender == address(bridge), "Message must come from bridge");
        require(bridge.messageSender() == FORK_MANAGER_SPECIAL_ADDRESS, "Message must come from L1 ForkManager");
        _;
    }

    constructor(address _realityETH, uint256 _dispute_fee, IAMB _bridge, address[] memory _initial_arbitrators) 
    {
        realityETH = RealityETH_ERC20_v3_0(_realityETH);
        dispute_fee = _dispute_fee;
        bridge = _bridge;
        for(uint256 i = 0; i<_initial_arbitrators.length; i++) {
            arbitrators[_initial_arbitrators[i]] = true;
        }
    }
	
    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @param question_id The question in question
    /// @dev Uses a general default, but can be over-ridden on a question-by-question basis.
    function getDisputeFee(bytes32 question_id)
    public view returns (uint256) {
        return dispute_fee;
    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev The bounty can be paid only in part, in which case the last person to pay will be considered the payer
    /// Will trigger an error if the notification fails, eg because the question has already been finalized
    /// @param question_id The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(bytes32 question_id, uint256 max_previous)
    external payable returns (bool) {

        uint256 arbitration_fee = getDisputeFee(question_id);
        require(arbitration_fee > 0, "The arbitrator must have set a non-zero fee for the question");

        require(msg.value >= arbitration_fee); 

        realityETH.notifyOfArbitrationRequest(question_id, msg.sender, max_previous);
        emit LogRequestArbitration(question_id, msg.value, msg.sender, 0);

        // Queue the question for arbitration by a whitelisted arbitrator
        // Anybody can take the question off the queue and submit it to a whitelisted arbitrator
        // They will have to pay the arbitration fee upfront
        // They can claim the bounty when they get an answer
        // If the arbitrator is removed in the meantime, they'll lose the money they spent on arbitration
        question_arbitrations[question_id].payer = msg.sender;
        question_arbitrations[question_id].bounty = msg.value;
        question_arbitrations[question_id].last_action_ts = block.timestamp;

        return true;

    }

    // This function is normally in Reality.eth.
    // We put it here so that we can be treated like Reality.eth from the pov of the arbitrator contract.

    /// @notice Notify the contract that the arbitrator has been paid for a question, freezing it pending their decision.
    /// @dev The arbitrator contract is trusted to only call this if they've been paid, and tell us who paid them.
    /// @param question_id The ID of the question
    /// @param requester The account that requested arbitration
    /// @param max_previous Only here for API compatibility
    function notifyOfArbitrationRequest(bytes32 question_id, address requester, uint256 max_previous)
    external {

        require(arbitrators[msg.sender], "Arbitrator must be on the whitelist");
        require(question_arbitrations[question_id].bounty > 0, "Question must be in the arbitration queue");

        // The only time you can pick up a question that's already being arbitrated is if it's been removed from the whitelist
        if (question_arbitrations[question_id].arbitrator != address(0)) {
            require(!arbitrators[question_arbitrations[question_id].arbitrator], "Question already taken, and the arbitrator who took it is still active");

            // Clear any in-progress data from the arbitrator that has now been removed
            question_arbitrations[question_id].msg_hash = 0x0;
            question_arbitrations[question_id].finalize_ts = 0;
        }

        question_arbitrations[question_id].payer = requester;
        question_arbitrations[question_id].arbitrator = msg.sender;

        emit LogNotifyOfArbitrationRequest(question_id, requester);
    }

    /// @notice Clear the arbitrator setting of an arbitrator that has been delisted
    /// @param question_id The question in question
    /// @dev Starts the clock ticking to allow us to cancelUnhandledArbitrationRequest
    /// @dev Not otherwise needed, if another arbitrator shows up they can just take the job from the delisted arbitrator
    function clearRequestFromRemovedArbitrator(bytes32 question_id)
    external {
        address old_arbitrator = question_arbitrations[question_id].arbitrator;
        require(old_arbitrator != address(0), "No arbitrator to remove");
        require(!arbitrators[old_arbitrator], "Arbitrator must no longer be on the whitelist");

        question_arbitrations[question_id].arbitrator = address(0);
        question_arbitrations[question_id].msg_hash = 0x0;
        question_arbitrations[question_id].finalize_ts = 0;

        question_arbitrations[question_id].last_action_ts = block.timestamp;
    }

    /// @notice Cancel the request for arbitration
    /// @param question_id The question in question
    /// @dev This is only done if nobody takes the request off the queue, probably because the fee is too low
    function cancelUnhandledArbitrationRequest(bytes32 question_id)
    external {
        uint256 last_action_ts = question_arbitrations[question_id].last_action_ts;
        require(last_action_ts > 0, "Question not found");

        require(question_arbitrations[question_id].arbitrator == address(0), "Question already accepted by an arbitrator");
        require(block.timestamp - last_action_ts > QUESTION_UNHANDLED_TIMEOUT, "You can only cancel questions that no arbitrator has accepted in a reasonable time");

        // Refund the arbitration bounty
        balanceOf[question_arbitrations[question_id].payer] = balanceOf[question_arbitrations[question_id].payer] + question_arbitrations[question_id].bounty;
        delete question_arbitrations[question_id];
        realityETH.cancelArbitration(question_id);
    }

    // The arbitrator submits the answer to us, instead of to realityETH
    // Instead of sending it to Reality.eth, we instead hold onto it for a challenge period in case someone disputes the arbitrator.
    // TODO: We may need assignWinnerAndSubmitAnswerByArbitrator here instead

    /// @notice Submit the arbitrator's answer to a question.
    /// @param question_id The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    /// @dev solc will complain about unsued params but they're used, just via msg.data
    function submitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address answerer)
    public 
    {
        require(question_arbitrations[question_id].arbitrator == msg.sender, "An arbitrator can only submit their own arbitration result");
        require(question_arbitrations[question_id].bounty > 0, "Question must be in the arbitration queue");

        bytes32 data_hash = keccak256(abi.encodePacked(question_id, answer, answerer));
        uint256 finalize_ts = block.timestamp + ARB_DISPUTE_TIMEOUT; 

        question_arbitrations[question_id].msg_hash = data_hash;
        question_arbitrations[question_id].finalize_ts = finalize_ts;
    }

    /// @notice Resubmit the arbitrator's answer to a question once the challenge period for it has passed
    /// @param question_id The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    function completeArbitration(bytes32 question_id, bytes32 answer, address answerer)
    external {

        address arbitrator = question_arbitrations[question_id].arbitrator;

        require(arbitrators[arbitrator], "Arbitrator must be whitelisted");
        require(!frozen_arbitrators[arbitrator], "Arbitrator must not be under dispute"); 

        bytes32 data_hash = keccak256(abi.encodePacked(question_id, answer, answerer));
        require(question_arbitrations[question_id].msg_hash == data_hash, "You must resubmit the parameters previously sent");

        uint256 finalize_ts = question_arbitrations[question_id].finalize_ts;
        require(finalize_ts > 0, "Submission must have been queued");
        require(finalize_ts < block.timestamp, "Challenge deadline must have passed");

        balanceOf[question_arbitrations[question_id].payer] = balanceOf[question_arbitrations[question_id].payer] + question_arbitrations[question_id].bounty;

        realityETH.submitAnswerByArbitrator(question_id, answer, answerer);
    }

    function freezeArbitrator(address arbitrator) 
    //    l1_forkmanager_only
    public {
        require(arbitrators[arbitrator], "Arbitrator not whitelisted in the first place");
        require(!frozen_arbitrators[arbitrator], "Arbitrator already frozen");
        frozen_arbitrators[arbitrator] = true;
    }

    function unfreezeArbitrator(address arbitrator) 
    l1_forkmanager_only
    public {
        require(arbitrators[arbitrator], "Arbitrator not whitelisted in the first place");
        require(frozen_arbitrators[arbitrator], "Arbitrator not already frozen");
        frozen_arbitrators[arbitrator] = false;
    }

    function addArbitrator(address arbitrator) 
        l1_forkmanager_only
    public {
        require(!arbitrators[arbitrator], "Arbitrator already whitelisted");
        arbitrators[arbitrator] = true;
    }

    function removeArbitrator(address arbitrator) 
        l1_forkmanager_only
    public {
        require(arbitrators[arbitrator], "Arbitrator already whitelisted");
        frozen_arbitrators[arbitrator] = false;
        arbitrators[arbitrator] = false;
    }

    function _numUnreservedTokens() 
    internal view returns (uint256) {
        return address(this).balance - reserved_tokens;
    }

    function reserveTokens(uint256 num, uint256 price, uint256 nonce)
    public {
        bytes32 resid = keccak256(abi.encodePacked(msg.sender, nonce));
        require(token_reservations[resid].reserved_ts == 0, "Nonce already used");

        require(_numUnreservedTokens() > num, "Not enough tokens unreserved");

        uint256 deposit = num * price / TOKEN_RESERVATION_DEPOSIT;
        payable(msg.sender).transfer(deposit);

        token_reservations[resid] = TokenReservation(
            msg.sender, 
            num,
            price,
            block.timestamp
        );
        reserved_tokens = reserved_tokens + num;
    }

    function outBidReservation(uint256 num, uint256 price, uint256 nonce, bytes32 resid) 
    external {

        require(token_reservations[resid].reserved_ts > 0, "Reservation you want to outbid does not exist");
        uint256 age = block.timestamp - token_reservations[resid].reserved_ts;
        require(age < TOKEN_RESERVATION_BIDDING_PERIOD, "Bidding period has passed");

        require(token_reservations[resid].num >= num, "More tokens requested than remain in the reservation"); 
        require(price > token_reservations[resid].price * 101/100, "You must bid at least 1% more than the previous bid");

        uint256 deposit_return = num * token_reservations[resid].price / TOKEN_RESERVATION_DEPOSIT;

        payable(token_reservations[resid].reserver).transfer(deposit_return);
        reserved_tokens = reserved_tokens - num;

        if (num == token_reservations[resid].num) {
            delete(token_reservations[resid]);
        } else {
            token_reservations[resid].num = token_reservations[resid].num - num;
        }

        return reserveTokens(num, price, nonce);
    }

    function cancelTimedOutReservation(bytes32 resid) 
    external {
        uint256 age = block.timestamp - token_reservations[resid].reserved_ts;
        require(age > TOKEN_RESERVATION_CLAIM_TIMEOUT, "Not timed out yet");
        reserved_tokens = reserved_tokens - token_reservations[resid].num;
        delete(token_reservations[resid]); 
    }

    function executeTokenSale(bytes32 resid, uint256 gov_tokens_paid) 
        l1_forkmanager_only
    external {
        uint256 age = block.timestamp - token_reservations[resid].reserved_ts;
        require(age > TOKEN_RESERVATION_BIDDING_PERIOD, "Bidding period has not yet passed");

        uint256 num = token_reservations[resid].num;
        uint256 price = token_reservations[resid].price;
        uint256 cost = price * num;
        require(gov_tokens_paid >= cost, "Insufficient gov tokens sent");
        reserved_tokens = reserved_tokens - num;
        payable(token_reservations[resid].reserver).transfer(num);

        delete(token_reservations[resid]); 
    }

    function realitio() 
    external view
    returns (address)
    {
        return address(realityETH);
    }

}
