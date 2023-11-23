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
    uint32 public constant L1_NETWORK_ID = 0;

    struct ChainInfo{
        address forkonomicToken;
        uint256 forkFee;
    }
    mapping(uint256 => ChainInfo) public chainInfo;

    // Questions are stored by isL2->forker->id
    // The forker is assumed to have created a unique id within itself for the dispute it's forking over
    mapping(bool=>mapping(address=>mapping(bytes32=>bytes32))) public forkQuestionResults;
    mapping(bool=>mapping(address=>mapping(bytes32=>uint256))) public questionToChainID;

    constructor(address _l2bridge, address _l1globalRouter) {
        l2bridge = _l2bridge; 
        l1globalRouter = _l1globalRouter;
    }

    modifier isUpToDate {
        require(chainInfo[block.chainid].forkonomicToken != address(0), "Current chain must be known");
        _;
    }

    modifier isNotUpToDate {
        require(chainInfo[block.chainid].forkonomicToken == address(0), "Current chain must be unknown");
        _;
    }

    function getForkonomicToken() external view isUpToDate returns(address) {
	return chainInfo[block.chainid].forkonomicToken;
    }

    function getForkFee() external view isUpToDate returns(uint256) {
	return chainInfo[block.chainid].forkFee;
    }

    function getForkQuestionResult(bool isL1, address forker, bytes32 questionId) external view isUpToDate returns(bytes32) {
	return forkQuestionResults[isL1][forker][questionId];
    }

    // Get a message from a contract we trust on L1 reporting to us the details of a chain.
    // It should only send us the current chain (normally) or a previous chain that's a parent of ours.
    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable {

        require(msg.sender == l2bridge, "not the expected bridge");
        require(_originAddress == l1globalRouter, "only l1globalRouter can call us");
        require(_originNetwork == L1_NETWORK_ID, "wrong origin network");

        (uint64 chainId, address forkonomicToken, uint256 forkFee, bool isL1, address forker, bytes32 questionId, bytes32 result) = abi.decode(_data, (uint64, address, uint256, bool, address, bytes32, bytes32));

        chainInfo[uint256(chainId)] = ChainInfo(forkonomicToken, forkFee);

        questionToChainID[isL1][forker][questionId] = chainId;
        forkQuestionResults[isL1][forker][questionId] = result;

    }

}
