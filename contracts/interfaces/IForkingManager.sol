// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "./IForkableStructure.sol";

interface IForkingManager is IForkableStructure {
    /// @dev Error thrown when the forking manager is not ready to fork
    error NotYetReadyToFork();
    /// @dev Error thrown when the forking manager is already initiated
    error ForkingAlreadyInitiated();

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

    function zkEVM() external returns (address);

    function bridge() external returns (address);

    function forkonomicToken() external returns (address);

    function globalExitRoot() external returns (address);

    function arbitrationFee() external returns (uint256);

    function disputeData()
        external
        returns (bool isL1, address disputeContract, bytes32 disputeContent);

    function executionTimeForProposal() external returns (uint256);

    function isForkingInitiated() external returns (bool);

    function isForkingExecuted() external returns (bool);

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

    /**
     * @notice Function to initialize the forking manager
     * @param _zkEVM Address of the zkEVM contract
     * @param _bridge Address of the bridge contract
     * @param _forkonomicToken Address of the forkonomic token contract
     * @param _parentContract Address of the parent contract
     * @param _globalExitRoot Address of the global exit root contract
     * @param _arbitrationFee Arbitration fee for the dispute
     * @param _chainIdManager Address of the chainIdManager contract
     * @param _forkPreparationTime Time to wait before the fork is initiated
     */
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee,
        address _chainIdManager,
        uint256 _forkPreparationTime
    ) external;

    function initiateFork(DisputeData memory _disputeData) external;
}
