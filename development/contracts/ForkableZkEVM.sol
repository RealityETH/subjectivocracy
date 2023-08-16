// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {PolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVM.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";

import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IForkableZkEVM} from "./interfaces/IForkableZkEVM.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";

contract ForkableZkEVM is ForkableStructure, IForkableZkEVM, PolygonZkEVM {
    // @inheritdoc IForkableZkEVM
    function initialize(
        address _forkmanager,
        address _parentContract,
        InitializePackedParameters calldata initializePackedParameters,
        bytes32 genesisRoot,
        string memory _trustedSequencerURL,
        string memory _networkName,
        string calldata _version,
        IPolygonZkEVMGlobalExitRoot _globalExitRootManager,
        IERC20Upgradeable _matic,
        IVerifierRollup _rollupVerifier,
        IPolygonZkEVMBridge _bridgeAddress
    ) external initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
        PolygonZkEVM.initialize(
            initializePackedParameters,
            genesisRoot,
            _trustedSequencerURL,
            _networkName,
            _version,
            _globalExitRootManager,
            _matic,
            _rollupVerifier,
            _bridgeAddress
        );
    }

    // @inheritdoc IForkableZkEVM
    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }

    ////////////////////////////////////////////////////////////////////////////
    // For the following functions a modifier called: onlyBeforeForking is added.
    // This ensure that the functions do not change the consolidated state after forking.
    ///////////////////////////////////////////////////////////////////////////

    function verifyBatches(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        bytes calldata proof
    ) public override onlyBeforeForking {
        PolygonZkEVM.verifyBatches(
            pendingStateNum,
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            newStateRoot,
            proof
        );
    }

    function verifyBatchesTrustedAggregator(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        bytes calldata proof
    ) public override onlyBeforeForking {
        PolygonZkEVM.verifyBatchesTrustedAggregator(
            pendingStateNum,
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            newStateRoot,
            proof
        );
    }

    function consolidatePendingState(
        uint64 pendingStateNum
    ) public override onlyBeforeForking {
        PolygonZkEVM.consolidatePendingState(pendingStateNum);
    }

    function overridePendingState(
        uint64 initPendingStateNum,
        uint64 finalPendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        bytes calldata proof
    ) public override onlyBeforeForking {
        PolygonZkEVM.overridePendingState(
            initPendingStateNum,
            finalPendingStateNum,
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            newStateRoot,
            proof
        );
    }

    // @dev: sequenceBatches can also change the consolidated state, and hence its prohibited to be called
    // after forking.
    function sequenceBatches(
        BatchData[] calldata batches,
        address l2Coinbase
    ) public override onlyBeforeForking {
        PolygonZkEVM.sequenceBatches(batches, l2Coinbase);
    }

    // @dev: The function proveNonDeterministicPendingState() should still be callable, as it
    // does not change the state root and only raises an emergency event.

    // @dev The activateEmergencyState modifier is not changed, as we will always want to be able to
    // itervene as an admin.
    // function activateEmergencyState()

    // @dev This deactivateEmergencyState modifier is not changed, as we will always want to be able to
    // itervene as an admin.
    // function deactivateEmergencyState()

    // @dev People will be allowed to force batches, because they can never be verified anyways
    // and hence will not have any impact on the state root.
    // See functions  sequenceForceBatches and forceBatch in the PolygonZkEVM contract.
}
