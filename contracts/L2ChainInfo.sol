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

contract L2ChainInfo is IBridgeMessageReceiver {
    /// @dev Error thrown when the chain info is not known
    error ChainInfoNotKnown();
    /// @dev Error thrown when the caller is not the bridge
    error OnlyBridge();
    /// @dev Error thrown when the origin is not the publisher
    error OriginMustBePublisher();
    /// @dev Error thrown when the origin network is not the L1 network
    error BadOriginNetwork();

    // These are the same for all forks
    address public l2Bridge;
    address public l1GlobalChainInfoPublisher;
    uint32 public constant L1_NETWORK_ID = 0;

    struct ChainInfo {
        address forkonomicToken;
        uint256 forkFee;
    }
    mapping(uint64 => ChainInfo) public chainInfo;

    // Questions are stored by isL2->forker->id
    // The forker is assumed to have created a unique id within itself for the dispute it's forking over
    mapping(bool => mapping(address => mapping(bytes32 => bytes32)))
        public forkQuestionResults;
    mapping(bool => mapping(address => mapping(bytes32 => uint64)))
        public questionToChainID;

    constructor(address _l2Bridge, address _l1GlobalChainInfoPublisher) {
        l2Bridge = _l2Bridge;
        l1GlobalChainInfoPublisher = _l1GlobalChainInfoPublisher;
    }

    modifier isUpToDate() {
        if (chainInfo[uint64(block.chainid)].forkonomicToken == address(0)) {
            revert ChainInfoNotKnown();
        }
        _;
    }

    modifier onlyBridge() {
        if (msg.sender != l2Bridge) {
            revert OnlyBridge();
        }
        _;
    }

    /*
     * @dev Get the forkonomic token
     * @return The forkonomic token
     */
    function getForkonomicToken() external view isUpToDate returns (address) {
        return chainInfo[uint64(block.chainid)].forkonomicToken;
    }

    /*
     * @dev Get the fee for a fork
     * @return The fee for a fork
     */
    function getForkFee() external view isUpToDate returns (uint256) {
        return chainInfo[uint64(block.chainid)].forkFee;
    }

    /**
     *@dev Get the result of a fork question
     *@param isL1 Whether the question was asked on L1
     *@param forker The address of the forker
     *@param questionId The question ID
     */
    function getForkQuestionResult(
        bool isL1,
        address forker,
        bytes32 questionId
    ) external view isUpToDate returns (bytes32) {
        return forkQuestionResults[isL1][forker][questionId];
    }

    /*
     * @dev Get a message via the bridge from a contract we trust on L1 reporting to us the details of a fork.
     * It should normally be used right after a fork to send us the current chain.
     * It could also send us information about a previous chain that's a parent of ours if we forked again before getting it for some reason.
     * @param _originAddress The address of the contract on L1 that sent the message
     * @param _originNetwork The network ID of the contract on L1 that sent the message
     * @param _data The data sent by the contract on L1
     */
    function onMessageReceived(
        address _originAddress,
        uint32 _originNetwork,
        bytes memory _data
    ) external payable onlyBridge {
        if (_originAddress != l1GlobalChainInfoPublisher) {
            revert OriginMustBePublisher();
        }
        if (_originNetwork != L1_NETWORK_ID) {
            revert BadOriginNetwork();
        }

        (
            uint64 chainId,
            address forkonomicToken,
            uint256 forkFee,
            bool isL1,
            address forker,
            bytes32 questionId,
            bytes32 result
        ) = abi.decode(
                _data,
                (uint64, address, uint256, bool, address, bytes32, bytes32)
            );

        chainInfo[chainId] = ChainInfo(forkonomicToken, forkFee);

        questionToChainID[isL1][forker][questionId] = chainId;
        forkQuestionResults[isL1][forker][questionId] = result;
    }
}
