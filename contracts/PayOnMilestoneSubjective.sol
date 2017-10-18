pragma solidity ^0.4.13;

contract RealityTokenAPI {
    function transfer(address _to, uint _value, bytes32 _branch) public returns (bool success);
    function balanceOf(address _owner, bytes32 _branch) constant public returns (uint balance);
    function getDataContract(bytes32 _branch) public constant returns (address); 
}

contract RealityCheckAPI {
    function getFinalAnswerIfMatches(bytes32 question_id, bytes32 content_hash, address arbitrator, uint256 min_timeout, uint256 min_bond) public constant returns (bytes32);
}

contract DataContract {
    function get(bytes32 k) public constant returns (bytes32);
}

contract PayOnMilestoneSubjective {

    address realitycheck;
    address token;
    address payee;
    bytes32 branch;

    function PayOnMilestone(address _realitycheck, address _token, address _payee) public {
        realitycheck = _realitycheck;
        token = _token;
        payee = _payee;
    }

    function isArbitratorValid(address _arbitrator, address data_cntrct) returns (bool) {
        bytes32 content_hash = keccak256(uint256(8), _arbitrator);
        uint256 valid_until = uint256(DataContract(data_cntrct).get(content_hash));
        return (valid_until > now);
    }

    function claim(bytes32 question_id, bytes32 _branch, address _arbitrator) public {
        bytes32 content_hash = keccak256(uint256(0), "Did Ed complete milestone 1?");
        bytes32 answer = RealityCheckAPI(realitycheck).getFinalAnswerIfMatches(
            question_id,
            content_hash, _arbitrator, 1 days, 1 ether
        );
        require(answer == bytes32(1));
        
        address data_cntrct = RealityTokenAPI(realitycheck).getDataContract(_branch);
        require(isArbitratorValid(_arbitrator, data_cntrct));

        uint256 tokens_held = RealityTokenAPI(token).balanceOf(this, _branch);
        RealityTokenAPI(token).transfer(payee, tokens_held, _branch);
    }

}
