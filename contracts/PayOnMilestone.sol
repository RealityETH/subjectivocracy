pragma solidity ^0.4.13;

contract ERC20API {
    function transfer(address _to, uint _value) public returns (bool success);
    function balanceOf(address _owner) constant public returns (uint balance);
}

contract RealityCheckAPI {
    function getFinalAnswerIfMatches(bytes32 question_id, bytes32 content_hash, address arbitrator, uint256 min_timeout, uint256 min_bond) public constant returns (bytes32);
}

contract PayOnMilestone {

    address realitycheck;
    address arbitrator;
    address token;
    address payee;

    function PayOnMilestone(address _realitycheck, address _token, address _arbitrator, address _payee) {
        realitycheck = _realitycheck;
        token = _token;
        arbitrator = _arbitrator;
        payee = _payee;
    }

    function claim(bytes32 question_id) {
        bytes32 content_hash = keccak256(0, "Did Ed complete milestone 1?");
        bytes32 answer = RealityCheckAPI(realitycheck).getFinalAnswerIfMatches(
            question_id,
            content_hash, arbitrator, 1 days, 1 ether
        );
        require(answer == bytes32(1));
        uint256 tokens_held = ERC20API(token).balanceOf(this);
        ERC20API(token).transfer(payee, tokens_held);
    }

}
