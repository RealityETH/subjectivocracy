// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/*
This contract lives on L2 and shares information about the chain.
It needs to get this information by being called after a fork.
We made it for the ForkArbitrator to get the result after a fork. 
Other contracts may also find it useful.
It must be called after a fork until it's updated.
Queries against it will revert until the update is done.

TODO: Should we somehow make it updateable even if you miss the fork window?
*/

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

contract L2ChainInfo is IBridgeMessageReceiver{

    // These should be fixed addresses that never change
    address public l2bridge; 
    address public l1globalRouter;
    uint32 public originNetwork;

    uint256 internal chainId;
    address internal forkonomicToken; // Not needed for reality.eth/arbitration stuff but it seems useful to have on L2
    address internal forkingManager; // Likewise
    uint256 internal forkFee;
    // uint256 internal totalSupply;

    mapping(bytes32=>bytes32) public forkQuestionResults;

    // We need a mapping of question to something to know if we have a result
    // Use chainId as it seems like it may be useful elsewhere
    // Another option would be to map the fork results to 1/2 instead of 0/1
    mapping(bytes32=>uint256) public questionToChainID;

    constructor(uint32 _originNetwork, address _l2bridge, address _l1globalRouter) {
	originNetwork = _originNetwork;
        l2bridge = _l2bridge; 
        l1globalRouter = _l1globalRouter;
    }

    modifier isUpToDate {
        require(block.chainid == chainId, "Chain ID must be up-to-date");
        _;
    }

    modifier isNotUpToDate {
        require(block.chainid != chainId, "Chain ID must be changed");
        _;
    }

    function getChainID() external view isUpToDate returns(uint256) {
	return chainId;
    }

    function getForkonomicToken() external view isUpToDate returns(address) {
	return forkonomicToken;
    }

    function getForkFee() external view isUpToDate returns(uint256) {
	return forkFee;
    }

    function getForkQuestionResult(bytes32 questionId) external view isUpToDate returns(bytes32) {
	return forkQuestionResults[questionId];
    }

    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable isNotUpToDate {

        require(msg.sender == l2bridge, "not the expected bridge");
        require(_originAddress == l1globalRouter, "only l1globalRouter can call us");
        require(_originNetwork == originNetwork, "wrong origin network");

        bytes32 _questionId; 
        bytes32 _result;

        (forkingManager, forkonomicToken, forkFee, _questionId, _result) = abi.decode(_data, (address, address, uint256, bytes32, bytes32));
        chainId = block.chainid;

        questionToChainID[_questionId] = chainId;

        // TODO: Make sure these questionIDs can't overlap.
        // Reality.eth won't make overlapping questions but in theory we allow things other than reality.eth.
        forkQuestionResults[_questionId] = _result;
    
    }

}
