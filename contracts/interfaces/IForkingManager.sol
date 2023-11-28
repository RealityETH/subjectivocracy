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

    // Struct containing the addresses of the new implementations
    struct NewImplementations {
        address bridgeImplementation;
        address zkEVMImplementation;
        address forkonomicTokenImplementation;
        address forkingManagerImplementation;
        address globalExitRootImplementation;
        address verifier;
        uint64 forkID;
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

    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee,
        address _chainIdManager
    ) external;

}
