pragma solidity ^0.4.13;

contract RealityTokenAPI {
    function transfer(address _to, uint _value) public returns (bool success);
    function balanceOf(address _owner) constant public returns (uint balance);
    function isWhitelisted(address arbitrator, bytes32 branch) constant public returns (bool val);
}

contract RealityCheckAPI {
    function getFinalAnswerIfMatches(bytes32 question_id, bytes32 content_hash, address arbitrator, uint256 min_timeout, uint256 min_bond) public constant returns (bytes32);
}

contract PayOnMilestoneSubjective {

    address realitycheck;
    address token;
    address payee;
    bytes32 branch;

    function PayOnMilestone(address _realitycheck, address _token, address _payee) {
        realitycheck = _realitycheck;
        token = _token;
        payee = _payee;
    }

    function claim(bytes32 question_id, bytes32 _branch, address _arbitrator) {
        bytes32 content_hash = keccak256(0, "Did Ed complete milestone 1?");
        bytes32 answer = RealityCheckAPI(realitycheck).getFinalAnswerIfMatches(
            question_id,
            content_hash, _arbitrator, 1 days, 1 ether
        );
        require(answer == bytes32(1));
        
        require(RealityTokenAPI(token).isWhitelisted(_arbitrator, _branch));
        uint256 tokens_held = RealityTokenAPI(token).balanceOf(this);
        RealityTokenAPI(token).transfer(payee, tokens_held);
    }

}
