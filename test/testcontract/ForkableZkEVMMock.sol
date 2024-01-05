pragma solidity ^0.8.20;

import {ForkableBridge} from "../../contracts/ForkableBridge.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {PolygonZkEVMBridge, IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {IForkableBridge} from "../../contracts/interfaces/IForkableBridge.sol";
import {IForkonomicToken} from "../../contracts/interfaces/IForkonomicToken.sol";
import {ForkableStructure} from "../../contracts/mixin/ForkableStructure.sol";
import {ForkableZkEVM} from "../../contracts//ForkableZkEVM.sol";

contract ForkableZkEVMMock is ForkableZkEVM {
    /**
     * @notice calculate accumulate input hash from parameters
     * @param currentAccInputHash Accumulate input hash
     * @param transactions Transactions
     * @param globalExitRoot Global Exit Root
     * @param timestamp Timestamp
     * @param sequencerAddress Sequencer address
     */
    function calculateAccInputHash(
        bytes32 currentAccInputHash,
        bytes memory transactions,
        bytes32 globalExitRoot,
        uint64 timestamp,
        address sequencerAddress
    ) public pure returns (bytes32) {
        return
            keccak256(
                abi.encodePacked(
                    currentAccInputHash,
                    keccak256(transactions),
                    globalExitRoot,
                    timestamp,
                    sequencerAddress
                )
            );
    }

    /**
     * @notice Return the next snark input
     * @param pendingStateNum Pending state num
     * @param initNumBatch Batch which the aggregator starts the verification
     * @param finalNewBatch Last batch aggregator intends to verify
     * @param newLocalExitRoot  New local exit root once the batch is processed
     * @param newStateRoot New State root once the batch is processed
     */
    function getNextSnarkInput(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot
    ) public view returns (uint256) {
        bytes32 oldStateRoot;
        uint64 currentLastVerifiedBatch = getLastVerifiedBatch();

        // Use pending state if specified, otherwise use consolidated state
        if (pendingStateNum != 0) {
            // Check that pending state exist
            // Already consolidated pending states can be used aswell
            require(
                pendingStateNum <= lastPendingState,
                "PolygonZkEVM::verifyBatches: pendingStateNum must be less or equal than lastPendingState"
            );

            // Check choosen pending state
            PendingState storage currentPendingState = pendingStateTransitions[
                pendingStateNum
            ];

            // Get oldStateRoot from pending batch
            oldStateRoot = currentPendingState.stateRoot;

            // Check initNumBatch matches the pending state
            require(
                initNumBatch == currentPendingState.lastVerifiedBatch,
                "PolygonZkEVM::verifyBatches: initNumBatch must match the pending state batch"
            );
        } else {
            // Use consolidated state
            oldStateRoot = batchNumToStateRoot[initNumBatch];
            require(
                oldStateRoot != bytes32(0),
                "PolygonZkEVM::verifyBatches: initNumBatch state root does not exist"
            );

            // Check initNumBatch is inside the range
            require(
                initNumBatch <= currentLastVerifiedBatch,
                "PolygonZkEVM::verifyBatches: initNumBatch must be less or equal than currentLastVerifiedBatch"
            );
        }

        // Check final batch
        require(
            finalNewBatch > currentLastVerifiedBatch,
            "PolygonZkEVM::verifyBatches: finalNewBatch must be bigger than currentLastVerifiedBatch"
        );

        // Get snark bytes
        bytes memory snarkHashBytes = getInputSnarkBytes(
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            oldStateRoot,
            newStateRoot
        );
        // Calulate the snark input
        uint256 inputSnark = uint256(sha256(snarkHashBytes)) % _RFIELD;

        return inputSnark;
    }

    /**
     * @notice Set state root
     * @param newStateRoot New State root ¡
     */
    function setStateRoot(
        bytes32 newStateRoot,
        uint64 batchNum
    ) public onlyOwner {
        batchNumToStateRoot[batchNum] = newStateRoot;
    }

    /**
     * @notice Set Sequencer
     * @param _numBatch New verifier
     */
    function setVerifiedBatch(uint64 _numBatch) public onlyOwner {
        lastVerifiedBatch = _numBatch;
    }

    /**
     * @notice Set Sequencer
     * @param _numBatch New verifier
     */
    function setSequencedBatch(uint64 _numBatch) public onlyOwner {
        lastBatchSequenced = _numBatch;
    }

    /**
     * @notice Set network name
     * @param _networkName New verifier
     */
    function setNetworkName(string memory _networkName) public onlyOwner {
        networkName = _networkName;
    }

    /**
     * @notice Update fee mock function
     * @param newLastVerifiedBatch New last verified batch
     */
    function updateBatchFee(uint64 newLastVerifiedBatch) public onlyOwner {
        _updateBatchFee(newLastVerifiedBatch);
    }

    /**
     * @notice Set sequencedBatches
     * @param batchNum bathc num
     * @param accInputData accInputData
     */
    function setSequencedBatches(
        uint64 batchNum,
        bytes32 accInputData,
        uint64 timestamp,
        uint64 lastPendingStateConsolidated
    ) public onlyOwner {
        sequencedBatches[batchNum] = SequencedBatchData({
            accInputHash: accInputData,
            sequencedTimestamp: timestamp,
            previousLastBatchSequenced: lastPendingStateConsolidated
        });
    }

    /**
     * @notice Allows an aggregator to verify multiple batches
     * @param initNumBatch Batch which the aggregator starts the verification
     * @param finalNewBatch Last batch aggregator intends to verify
     * @param newLocalExitRoot  New local exit root once the batch is processed
     * @param newStateRoot New State root once the batch is processed
     * @param proofA zk-snark input
     * @param proofB zk-snark input
     * @param proofC zk-snark input
     */
    function trustedVerifyBatchesMock(
        uint64 pendingStateNum,
        uint64 initNumBatch,
        uint64 finalNewBatch,
        bytes32 newLocalExitRoot,
        bytes32 newStateRoot,
        uint256[2] calldata proofA,
        uint256[2][2] calldata proofB,
        uint256[2] calldata proofC
    ) public onlyOwner {
        bytes32 oldStateRoot;
        uint64 currentLastVerifiedBatch = getLastVerifiedBatch();

        // Use pending state if specified, otherwise use consolidated state
        if (pendingStateNum != 0) {
            // Check that pending state exist
            // Already consolidated pending states can be used aswell
            require(
                pendingStateNum <= lastPendingState,
                "PolygonZkEVM::verifyBatches: pendingStateNum must be less or equal than lastPendingState"
            );

            // Check choosen pending state
            PendingState storage currentPendingState = pendingStateTransitions[
                pendingStateNum
            ];

            // Get oldStateRoot from pending batch
            oldStateRoot = currentPendingState.stateRoot;

            // Check initNumBatch matches the pending state
            require(
                initNumBatch == currentPendingState.lastVerifiedBatch,
                "PolygonZkEVM::verifyBatches: initNumBatch must match the pending state batch"
            );
        } else {
            // Use consolidated state
            oldStateRoot = batchNumToStateRoot[initNumBatch];
            require(
                oldStateRoot != bytes32(0),
                "PolygonZkEVM::verifyBatches: initNumBatch state root does not exist"
            );

            // Check initNumBatch is inside the range
            require(
                initNumBatch <= currentLastVerifiedBatch,
                "PolygonZkEVM::verifyBatches: initNumBatch must be less or equal than currentLastVerifiedBatch"
            );
        }

        // Check final batch
        require(
            finalNewBatch > currentLastVerifiedBatch,
            "PolygonZkEVM::verifyBatches: finalNewBatch must be bigger than currentLastVerifiedBatch"
        );

        // Get snark bytes
        bytes memory snarkHashBytes = getInputSnarkBytes(
            initNumBatch,
            finalNewBatch,
            newLocalExitRoot,
            oldStateRoot,
            newStateRoot
        );

        // // Calulate the snark input
        // uint256 inputSnark = uint256(sha256(snarkHashBytes)) % _RFIELD;

        // // Verify proof
        // require(
        //     rollupVerifier.verifyProof(proofA, proofB, proofC, [inputSnark]),
        //     "PolygonZkEVM::verifyBatches: INVALID_PROOF"
        // );

        // // Get MATIC reward
        // matic.safeTransfer(
        //     msg.sender,
        //     calculateRewardPerBatch() *
        //         (finalNewBatch - currentLastVerifiedBatch)
        // );

        // Consolidate state
        lastVerifiedBatch = finalNewBatch;
        batchNumToStateRoot[finalNewBatch] = newStateRoot;

        // Clean pending state if any
        if (lastPendingState > 0) {
            lastPendingState = 0;
            lastPendingStateConsolidated = 0;
        }

        // Interact with globalExitRootManager
        globalExitRootManager.updateExitRoot(newLocalExitRoot);

        emit VerifyBatchesTrustedAggregator(
            finalNewBatch,
            newStateRoot,
            msg.sender
        );
    }
}
