pragma solidity ^0.8.17;

import {IForkableStructure} from "./IForkableStructure.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";

interface IForkableZkEVM is IForkableStructure, IPolygonZkEVM {
    // @dev: This function is used to initialize the contract.
    // @params forkmanager: The address of the forkmanager contract.
    // @params parentContract: The address of the parent contract.
    // @params initializePackedParameters: The packed parameters for the initialization of the contract.
    // @params genesisRoot: The genesis root of the contract.
    // @params _trustedSequencerURL: The URL of the trusted sequencer.
    // @params _networkName: The name of the network.
    // @params _version: The version of the contract.
    // @params _globalExitRootManager: The address of the global exit root manager.
    // @params _matic: The address of the forkable token to pay sequencer fees
    // @params _rollupVerifier: The address of the rollup verifier.
    // @params _bridgeAddress: The address of the bridge contract.
    function initialize(
        address forkmanager,
        address parentContract,
        InitializePackedParameters calldata initializePackedParameters,
        bytes32 genesisRoot,
        string memory _trustedSequencerURL,
        string memory _networkName,
        string calldata _version,
        IPolygonZkEVMGlobalExitRoot _globalExitRootManager,
        IERC20Upgradeable _matic,
        IVerifierRollup _rollupVerifier,
        IPolygonZkEVMBridge _bridgeAddress
    ) external;

    // @dev: This function is used to create the children contracts.
    // The initialization of the children contracts should be called in the same transaction
    // as the creation of the children contracts.
    // @params implemation: The implementation of the children contracts.
    function createChildren(
        address implementation
    ) external returns (address, address);
}
