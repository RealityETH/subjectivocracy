// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

/*
This contract lives on L2 and shares information about the chain.
It needs to get this information by being called after a fork.
We made it for the ForkArbitrator to get the result after a fork. 
Other contracts may also find it useful.
It must be called after a fork until it's updated.
Queries against it will revert until the update is done.
*/

import {IBridgeMessageReceiver} from "@RealityETH/zkevm-contracts/contracts/interfaces/IBridgeMessageReceiver.sol";

contract L2ChainInfo is IBridgeMessageReceiver{

    // These should be fixed addresses that never change
    address public l2bridge; 
    address public l1globalRouter;
    uint32 public originNetwork;

    uint256 internal chainId;
    address internal forkonomicToken; // Not needed for reality.eth/arbitration stuff but it seems useful to have on L2
    uint256 internal forkFee;
    // uint256 internal totalSupply;

    mapping(bytes32=>bytes32) internal forkQuestionResults;

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
        require(block.chainid != chainId, "Chain ID must have changed since last update");
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

    // From polygon-zkevm-messenger-l1-to-l2-example
    function onMessageReceived(address _originAddress, uint32 _originNetwork, bytes memory _data) external payable isUpToDate {
      require(msg.sender == l2bridge, "not the expected bridge");
      require(_originAddress == l1globalRouter, "only l1globalRouter can call us");
      require(_originNetwork == originNetwork, "wrong origin network");

      // As we only accept the one message we do the check for the caller here instead of in the handling function
      // caller = originAddress;
      (bool success, ) = address(this).call(_data);
      if (!success) {
        revert('onMessageReceived execution failed');
      }
      // caller = address(0);
    }

    // NB This is external but it gets called by ourselves
    function updateChainInfo(
        address _forkonomicToken,
        uint256 _forkFee,
        bytes32 _questionId, 
        bytes32 _result 
    ) isNotUpToDate external {
        require(msg.sender == address(this), "Message should come via bridge, then be relayed by ourselves");

	// No need to check the caller as this is done in onMessageReceived

	// TODO: We could also send forkmanager and stuff
        forkonomicToken = _forkonomicToken;
        forkFee = _forkFee;
        chainId = block.chainid;

        // TODO: Make sure these questionIDs can't overlap.
        // Reality.eth won't make overlapping questions but in theory we allow things other than reality.eth.
        forkQuestionResults[_questionId] = _result;
        
    }

}
