// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import './IArbitrator.sol';
import './IRealityETH.sol';
import './IERC20.sol';
import './Owned.sol';

contract Arbitrator is Owned, IArbitrator {

    IRealityETH public realitio;

    mapping(bytes32 => uint256) public arbitration_bounties;

    uint256 dispute_fee;
    mapping(bytes32 => uint256) custom_dispute_fees;

    string public metadata;

    event LogRequestArbitration(
        bytes32 indexed question_id,
        uint256 fee_paid,
        address requester,
        uint256 remaining
    );

    event LogSetRealitio(
        address realitio
    );

    event LogSetQuestionFee(
        uint256 fee
    );


    event LogSetDisputeFee(
        uint256 fee
    );

    event LogSetCustomDisputeFee(
        bytes32 indexed question_id,
        uint256 fee
    );

    /// @notice Constructor. Sets the deploying address as owner.
    constructor() {
        owner = msg.sender;
    }

    /// @notice Returns the Realitio contract address - deprecated in favour of realitio()
    function realitycheck() 
    external view returns(IRealityETH) {
        return realitio;
    }

    /// @notice Set the Reality Check contract address
    /// @param addr The address of the Reality Check contract
    function setRealitio(address addr) 
        onlyOwner 
    public {
        realitio = IRealityETH(addr);
        emit LogSetRealitio(addr);
    }

    /// @notice Set the default fee
    /// @param fee The default fee amount
    function setDisputeFee(uint256 fee) 
        onlyOwner 
    public {
        dispute_fee = fee;
        emit LogSetDisputeFee(fee);
    }

    /// @notice Set a custom fee for this particular question
    /// @param question_id The question in question
    /// @param fee The fee amount
    function setCustomDisputeFee(bytes32 question_id, uint256 fee) 
        onlyOwner 
    public {
        custom_dispute_fees[question_id] = fee;
        emit LogSetCustomDisputeFee(question_id, fee);
    }

    /// @notice Return the dispute fee for the specified question. 0 indicates that we won't arbitrate it.
    /// @param question_id The question in question
    /// @dev Uses a general default, but can be over-ridden on a question-by-question basis.
    function getDisputeFee(bytes32 question_id) 
    public view returns (uint256) {
        return (custom_dispute_fees[question_id] > 0) ? custom_dispute_fees[question_id] : dispute_fee;
    }

    /// @notice Set a fee for asking a question with us as the arbitrator
    /// @param fee The fee amount
    /// @dev Default is no fee. Unlike the dispute fee, 0 is an acceptable setting.
    /// You could set an impossibly high fee if you want to prevent us being used as arbitrator unless we submit the question.
    /// (Submitting the question ourselves is not implemented here.)
    /// This fee can be used as a revenue source, an anti-spam measure, or both.
    function setQuestionFee(uint256 fee) 
        onlyOwner 
    public {
        realitio.setQuestionFee(fee);
        emit LogSetQuestionFee(fee);
    }

    /// @notice Submit the arbitrator's answer to a question.
    /// @param question_id The question in question
    /// @param answer The answer
    /// @param answerer The answerer. If arbitration changed the answer, it should be the payer. If not, the old answerer.
    function submitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address answerer) 
        onlyOwner 
    public {
        delete arbitration_bounties[question_id];
        realitio.submitAnswerByArbitrator(question_id, answer, answerer);
    }

    /// @notice Submit the arbitrator's answer to a question, assigning the winner automatically.
    /// @param question_id The question in question
    /// @param answer The answer
    /// @param payee_if_wrong The account to by credited as winner if the last answer given is wrong, usually the account that paid the arbitrator
    /// @param last_history_hash The history hash before the final one
    /// @param last_answer_or_commitment_id The last answer given, or the commitment ID if it was a commitment.
    /// @param last_answerer The address that supplied the last answer
    function assignWinnerAndSubmitAnswerByArbitrator(bytes32 question_id, bytes32 answer, address payee_if_wrong, bytes32 last_history_hash, bytes32 last_answer_or_commitment_id, address last_answerer) 
        onlyOwner 
    public {
        delete arbitration_bounties[question_id];
        realitio.assignWinnerAndSubmitAnswerByArbitrator(question_id, answer, payee_if_wrong, last_history_hash, last_answer_or_commitment_id, last_answerer);
    }

    /// @notice Cancel a previous arbitration request
    /// @dev This is intended for situations where the arbitration is happening non-atomically and the fee or something change.
    /// @param question_id The question in question
    function cancelArbitration(bytes32 question_id) 
        onlyOwner 
    public {
        realitio.cancelArbitration(question_id);
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

        arbitration_bounties[question_id] += msg.value;
        uint256 paid = arbitration_bounties[question_id];

        if (paid >= arbitration_fee) {
            realitio.notifyOfArbitrationRequest(question_id, msg.sender, max_previous);
            emit LogRequestArbitration(question_id, msg.value, msg.sender, 0);
            return true;
        } else {
            require(!realitio.isFinalized(question_id), "The question must not have been finalized");
            emit LogRequestArbitration(question_id, msg.value, msg.sender, arbitration_fee - paid);
            return false;
        }

    }

    /// @notice Withdraw any accumulated ETH fees to the specified address
    /// @param addr The address to which the balance should be sent
    function withdraw(address addr) 
        onlyOwner 
    public {
        payable(addr).transfer(address(this).balance); 
    }

    /// @notice Withdraw any accumulated token fees to the specified address
    /// @param addr The address to which the balance should be sent
    /// @dev Only needed if the Realitio contract used is using an ERC20 token
    /// @dev Also only normally useful if a per-question fee is set, otherwise we only have ETH.
    function withdrawERC20(IERC20 _token, address addr) 
        onlyOwner 
    public {
        uint256 bal = _token.balanceOf(address(this));
        IERC20(_token).transfer(addr, bal); 
    }

    receive() 
    external payable {
    }

    /// @notice Withdraw any accumulated question fees from the specified address into this contract
    /// @dev Funds can then be liberated from this contract with our withdraw() function
    /// @dev This works in the same way whether the realitio contract is using ETH or an ERC20 token
    function callWithdraw() 
        onlyOwner 
    public {
        realitio.withdraw(); 
    }

    /// @notice Set a metadata string, expected to be JSON, containing things like arbitrator TOS address
    function setMetaData(string memory _metadata) 
        onlyOwner
    external {
        metadata = _metadata;
    }

}
