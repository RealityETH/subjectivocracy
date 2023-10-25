// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

import "./mixin/BalanceHolder.sol";

import "./interfaces/IRealityETH.sol";

import "./interfaces/IArbitrator.sol";
import "./interfaces/IERC20.sol";

/*
This contract sits between a Reality.eth instance and an Arbitrator.
It manages a allowlist of arbitrators, and makes sure questions can be sent to an arbitrator on the allowlist.
When called on to arbitrate, it pays someone to send out the arbitration job to an arbitrator on the allowlist.
Arbitrators can be disputed on L1.
To Reality.eth it looks like a normal arbitrator, implementing the Arbitrator interface.
To the normal Arbitrator contracts that does its arbitration jobs, it looks like Reality.eth.
*/

contract AdjudicationFramework is BalanceHolder {

    // From RealityETH
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

    uint256 public constant ARB_DISPUTE_TIMEOUT = 86400;
    uint256 public constant QUESTION_UNHANDLED_TIMEOUT = 86400;

    uint256 public constant TOKEN_RESERVATION_BIDDING_PERIOD = 86400; // After you make a bid, people have 1 day to outbid you
    uint256 public constant TOKEN_RESERVATION_CLAIM_TIMEOUT = 864000; // After a bid is accepted, you have 9 days to complete it or you can lose your deposit
    uint256 public constant TOKEN_RESERVATION_DEPOSIT = 10; // 1/10, ie 10%

    uint32 constant REALITY_ETH_TIMEOUT = 86400;
    uint32 constant REALITY_ETH_BOND_ARBITRATOR_ADD = 10000;
    uint32 constant REALITY_ETH_BOND_ARBITRATOR_REMOVE = 10000;
    uint32 constant REALITY_ETH_BOND_ARBITRATOR_FREEZE = 20000;

    string constant QUESTION_DELIM = "\u241f";
    uint256 constant TEMPLATE_ID_ADD_ARBITRATOR = 1;
    uint256 constant TEMPLATE_ID_REMOVE_ARBITRATOR = 2;

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

    // AllowList of acceptable arbitrators
    mapping(address => bool) public arbitrators;

    // List of arbitrators that are currently being challenged
    mapping(address => bool) public frozen_arbitrators;

    // TODO: Check if we need this, if we do put it in a shareable place to go with the l1 realityeth
    enum PropositionType {
        NONE,
        ADD_ARBITRATOR,
        REMOVE_ARBITRATOR,
        UPGRADE_BRIDGE
    }

    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition{
        PropositionType proposition_type;
        address arbitrator;
    }
    mapping(bytes32 => ArbitratorProposition) propositions;

    IRealityETH public realityETH;

    // Arbitrator used for requesting a fork in the L1 chain in add/remove propositions
    address public forkArbitrator;

    uint256 public dispute_fee;

    struct ArbitrationRequest {
        address arbitrator;
        address payer;
        uint256 bounty;
        bytes32 msg_hash;
        uint256 finalize_ts;
        uint256 last_action_ts;
    }

    mapping(bytes32 => ArbitrationRequest) public question_arbitrations;

    /*
    // TODO: Work out how this is implemented in xdai or whatever we use
    modifier l1_forkmanager_only() {
        require(msg.sender == address(bridge), "Message must come from bridge");
        require(
            bridge.messageSender() == FORK_MANAGER_SPECIAL_ADDRESS,
            "Message must come from L1 ForkManager"
        );
        _;
    }
    */

    // TODO: Create the templates here?
    constructor(
        address _realityETH,
        uint256 _dispute_fee,
        address _forkArbitrator
        //address[] memory _initial_arbitrators
    ) {
        realityETH = IRealityETH(_realityETH);
        dispute_fee = _dispute_fee;
        forkArbitrator = _forkArbitrator;
/*
        for (uint256 i = 0; i < _initial_arbitrators.length; i++) {
            arbitrators[_initial_arbitrators[i]] = true;
        }
*/
    }

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @dev Uses a general default, but can be over-ridden on a question-by-question basis.
    function getDisputeFee(bytes32) public view returns (uint256) {
        // Todo: make it depend on the question
        return dispute_fee;
    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @dev The bounty can be paid only in part, in which case the last person to pay will be considered the payer
    /// Will trigger an error if the notification fails, eg because the question has already been finalized
    /// @param question_id The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitration(
        bytes32 question_id,
        uint256 max_previous
    ) external payable returns (bool) {
        uint256 arbitration_fee = getDisputeFee(question_id);
        require(
            arbitration_fee > 0,
            "The arbitrator must have set a non-zero fee for the question"
        );
        require(msg.value >= arbitration_fee);

        realityETH.notifyOfArbitrationRequest(
            question_id,
            msg.sender,
            max_previous
        );
        emit LogRequestArbitration(question_id, msg.value, msg.sender, 0);

        // Queue the question for arbitration by a allowlisted arbitrator
        // Anybody can take the question off the queue and submit it to a allowlisted arbitrator
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
    function notifyOfArbitrationRequest(
        bytes32 question_id,
        address requester,
        uint256
    ) external {
        require(arbitrators[msg.sender], "Arbitrator must be on the allowlist");
        require(
            question_arbitrations[question_id].bounty > 0,
            "Question must be in the arbitration queue"
        );

        // The only time you can pick up a question that's already being arbitrated is if it's been removed from the allowlist
        if (question_arbitrations[question_id].arbitrator != address(0)) {
            require(
                !arbitrators[question_arbitrations[question_id].arbitrator],
                "Question already taken, and the arbitrator who took it is still active"
            );

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
    function clearRequestFromRemovedArbitrator(bytes32 question_id) external {
        address old_arbitrator = question_arbitrations[question_id].arbitrator;
        require(old_arbitrator != address(0), "No arbitrator to remove");
        require(
            !arbitrators[old_arbitrator],
            "Arbitrator must no longer be on the allowlist"
        );

        question_arbitrations[question_id].arbitrator = address(0);
        question_arbitrations[question_id].msg_hash = 0x0;
        question_arbitrations[question_id].finalize_ts = 0;

        question_arbitrations[question_id].last_action_ts = block.timestamp;
    }

    /// @notice Cancel the request for arbitration
    /// @param question_id The question in question
    /// @dev This is only done if nobody takes the request off the queue, probably because the fee is too low
    function cancelUnhandledArbitrationRequest(bytes32 question_id) external {
        uint256 last_action_ts = question_arbitrations[question_id]
            .last_action_ts;
        require(last_action_ts > 0, "Question not found");

        require(
            question_arbitrations[question_id].arbitrator == address(0),
            "Question already accepted by an arbitrator"
        );
        require(
            block.timestamp - last_action_ts > QUESTION_UNHANDLED_TIMEOUT,
            "You can only cancel questions that no arbitrator has accepted in a reasonable time"
        );

        // Refund the arbitration bounty
        balanceOf[question_arbitrations[question_id].payer] =
            balanceOf[question_arbitrations[question_id].payer] +
            question_arbitrations[question_id].bounty;
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
    function submitAnswerByArbitrator(
        bytes32 question_id,
        bytes32 answer,
        address answerer
    ) public {
        require(
            question_arbitrations[question_id].arbitrator == msg.sender,
            "An arbitrator can only submit their own arbitration result"
        );
        require(
            question_arbitrations[question_id].bounty > 0,
            "Question must be in the arbitration queue"
        );

        bytes32 data_hash = keccak256(
            abi.encodePacked(question_id, answer, answerer)
        );
        uint256 finalize_ts = block.timestamp + ARB_DISPUTE_TIMEOUT;

        question_arbitrations[question_id].msg_hash = data_hash;
        question_arbitrations[question_id].finalize_ts = finalize_ts;
    }

    /// @notice Resubmit the arbitrator's answer to a question once the challenge period for it has passed
    /// @param question_id The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    function completeArbitration(
        bytes32 question_id,
        bytes32 answer,
        address answerer
    ) external {
        address arbitrator = question_arbitrations[question_id].arbitrator;

        require(arbitrators[arbitrator], "Arbitrator must be allowlisted");
        require(
            !frozen_arbitrators[arbitrator],
            "Arbitrator must not be under dispute"
        );

        bytes32 data_hash = keccak256(
            abi.encodePacked(question_id, answer, answerer)
        );
        require(
            question_arbitrations[question_id].msg_hash == data_hash,
            "You must resubmit the parameters previously sent"
        );

        uint256 finalize_ts = question_arbitrations[question_id].finalize_ts;
        require(finalize_ts > 0, "Submission must have been queued");
        require(
            finalize_ts < block.timestamp,
            "Challenge deadline must have passed"
        );

        balanceOf[question_arbitrations[question_id].payer] =
            balanceOf[question_arbitrations[question_id].payer] +
            question_arbitrations[question_id].bounty;

        realityETH.submitAnswerByArbitrator(question_id, answer, answerer);
    }


    // Governance (including adding and removing arbitrators from the allowlist) has two steps:
    // 1) Create question
    // 2) Complete operation (if proposition succeeded) or nothing if it failed

    // For time-sensitive operations, we also freeze any interested parties, so
    // 1) Create question
    // 2) Prove sufficient bond posted, freeze
    // 3) Complete operation or Undo freeze

    function _toString(bytes memory data)
    internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < data.length; i++) {
                str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
                str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }


    function beginAddArbitratorToAllowList(address arbitrator_to_add)
    external returns (bytes32) {
        string memory question = _toString(abi.encodePacked(address(this), QUESTION_DELIM, arbitrator_to_add));
        bytes32 question_id = realityETH.askQuestionWithMinBond(TEMPLATE_ID_ADD_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0, REALITY_ETH_BOND_ARBITRATOR_ADD);
        require(propositions[question_id].proposition_type == PropositionType.NONE, "Proposition already exists");
        propositions[question_id] = ArbitratorProposition(PropositionType.ADD_ARBITRATOR, arbitrator_to_add);
        return question_id;
    }

    function beginRemoveArbitratorFromAllowList(address arbitrator_to_remove)
    external returns (bytes32) {
        string memory question = _toString(abi.encodePacked(address(this), QUESTION_DELIM, arbitrator_to_remove));
        bytes32 question_id = realityETH.askQuestionWithMinBond(TEMPLATE_ID_REMOVE_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0, REALITY_ETH_BOND_ARBITRATOR_REMOVE);
        require(propositions[question_id].proposition_type == PropositionType.NONE, "Proposition already exists");
        propositions[question_id] = ArbitratorProposition(PropositionType.REMOVE_ARBITRATOR, arbitrator_to_remove);

        // TODO: Should we automatically do a freeze here if the bond is high enough?

        return question_id;
    }

    function executeAddArbitratorToAllowList(bytes32 question_id) external {
        require(propositions[question_id].proposition_type == PropositionType.ADD_ARBITRATOR, "Wrong Proposition type");
        address arbitrator = propositions[question_id].arbitrator;
        require(!arbitrators[arbitrator], "Arbitrator already on allowlist");
        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Question did not return yes");
        delete(propositions[question_id]);
        arbitrators[arbitrator] = true;
    }

    function executeRemoveArbitratorFromAllowList(bytes32 question_id) external {
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Wrong Proposition type");
        address arbitrator = propositions[question_id].arbitrator;
        require(arbitrators[arbitrator], "Arbitrator not on allowlist in the first place");
        frozen_arbitrators[arbitrator] = false;
        delete(propositions[question_id]);
        arbitrators[arbitrator] = false;
    }

    // When an arbitrator is listed for removal, they can be frozen given a sufficient bond
    function freezeArbitrator(
        bytes32 question_id
    ) public {
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Wrong Proposition type");
        address arbitrator = propositions[question_id].arbitrator;

        require(
            arbitrators[arbitrator],
            "Arbitrator not allowlisted in the first place"
        );
        require(!frozen_arbitrators[arbitrator], "Arbitrator already frozen");

        // Require a bond of at least the specified level
        // This is only relevant if REALITY_ETH_BOND_ARBITRATOR_FREEZE is higher than REALITY_ETH_BOND_ARBITRATOR_REMOVE
        require(realityETH.getBond(question_id) >= REALITY_ETH_BOND_ARBITRATOR_FREEZE, "Bond too low to freeze");

        // TODO: Do we want this? Freeze can be prevented by changing the answer after the bond is submitted
        // Otherwise need a history to prove that the answer was given earlier with this bond
        require(realityETH.getBestAnswer(question_id) == bytes32(uint256(1)), "Best answer is not yes");

        frozen_arbitrators[arbitrator] = true;
    }

    // TODO: We may need to restructure the data to allow the unfreeze
    // Think about how possible multiple propositions should work
    function unfreezeArbitrator(address arbitrator) public {
        require(
            arbitrators[arbitrator],
            "Arbitrator not allowlisted in the first place"
        );
        require(
            frozen_arbitrators[arbitrator],
            "Arbitrator not already frozen"
        );
        frozen_arbitrators[arbitrator] = false;
    }


    function realitio() external view returns (address) {
        return address(realityETH);
    }



}
