// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "./IForkableStructure.sol";

interface IForkingManager is IForkableStructure {

    // Dispute contract and call to identify the dispute
    // that will be used to initiate/justify the fork
    struct DisputeData {
        bool isL1;
        address disputeContract;
        bytes32 disputeContent;
    }

    struct NewImplementations {
        address bridgeImplementation;
        address zkEVMImplementation;
        address forkonomicTokenImplementation;
        address forkingManagerImplementation;
        address globalExitRootImplementation;
        address verifier;
        uint64 forkID;
    }

    function zkEVM() external returns (address);
    function bridge() external returns (address);
    function forkonomicToken() external returns (address);
    function globalExitRoot() external returns (address);
    function arbitrationFee() external returns (uint256);
    function disputeData() external returns (DisputeData memory);

    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee,
        address _chainIdManager
    ) external;

    function initiateFork(
        DisputeData memory _disputeData,
        NewImplementations calldata newImplementations
    ) external;

}
