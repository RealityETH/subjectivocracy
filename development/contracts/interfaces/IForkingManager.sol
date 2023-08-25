// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {IForkableStructure} from "./IForkableStructure.sol";

interface IForkingManager is IForkableStructure {
    // Dispute contract and call to identify the dispute
    // that will be used to initiate/justify the fork
    struct DisputeData {
        address disputeContract;
        bytes disputeCall;
    }

    // Struct containing the addresses of the new implementations
    struct NewImplementations {
        address bridgeImplementation;
        address zkEVMImplementation;
        address forkonomicTokenImplementation;
        address forkingManagerImplementation;
        address globalExitRootImplementation;
        address verifier;
    }

    // Struct that holds an address pair used to store the new child contracts
    struct AddressPair {
        address one;
        address two;
    }

    // Struct containing the addresses of the new instances
    struct NewInstances {
        AddressPair forkingManager;
        AddressPair bridge;
        AddressPair zkEVM;
        AddressPair forkonomicToken;
        AddressPair globalExitRoot;
    }

    // Struct containing the data for the paid fork
    struct ForkProposal {
        DisputeData disputeData;
        NewImplementations proposedImplementations;
        uint256 executionTime;
    }

    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee,
        ForkProposal[] memory proposals
    ) external;
}
