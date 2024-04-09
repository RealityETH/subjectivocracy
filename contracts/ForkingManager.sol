// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IPolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMGlobalExitRoot.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {IBasePolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMBridge.sol";
import {IPolygonZkEVMBridge} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVMBridge.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {IForkableBridge} from "./interfaces/IForkableBridge.sol";
import {IForkableZkEVM} from "./interfaces/IForkableZkEVM.sol";
import {IForkingManager} from "./interfaces/IForkingManager.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {IForkableGlobalExitRoot} from "./interfaces/IForkableGlobalExitRoot.sol";
import {ChainIdManager} from "./ChainIdManager.sol";

contract ForkingManager is IForkingManager, ForkableStructure {
    using SafeERC20 for IERC20;

    // The depth of the deposit contract tree
    // Constant is a duplication of the constant in the zkEVM bridge contract
    uint256 public constant DEPOSIT_CONTRACT_TREE_DEPTH = 32;

    // Address of the forkable system
    address public zkEVM;
    address public bridge;
    address public forkonomicToken;
    address public globalExitRoot;
    address public chainIdManager;

    // Fee that needs to be paid to initiate a fork
    uint256 public arbitrationFee;

    // Following variables are defined during the fork proposal
    DisputeData public disputeData;
    uint256 public executionTimeForProposal;
    uint256 public forkPreparationTime;

    // variables to store the reserved chainIds for the forks
    uint64 public reservedChainIdForFork1;
    uint64 public reservedChainIdForFork2;

    /// @inheritdoc IForkingManager
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee,
        address _chainIdManager,
        uint256 _forkPreparationTime
    ) external initializer {
        zkEVM = _zkEVM;
        bridge = _bridge;
        forkonomicToken = _forkonomicToken;
        parentContract = _parentContract;
        globalExitRoot = _globalExitRoot;
        arbitrationFee = _arbitrationFee;
        chainIdManager = _chainIdManager;
        executionTimeForProposal = 0;
        forkPreparationTime = _forkPreparationTime;
        ForkableStructure.initialize(address(this), _parentContract);
    }

    function isForkingInitiated() external view returns (bool) {
        return (executionTimeForProposal > 0);
    }

    function isForkingExecuted() external view returns (bool) {
        return (children[0] != address(0) || children[1] != address(0));
    }

    /**
     * @notice function to initiate and schedule the fork
     * @param _disputeData the dispute contract and call to identify the dispute
     */
    function initiateFork(
        DisputeData memory _disputeData
    ) external onlyBeforeForking {
        if (executionTimeForProposal != 0) {
            revert ForkingAlreadyInitiated();
        }
        // Charge the forking fee
        IERC20(forkonomicToken).safeTransferFrom(
            msg.sender,
            address(this),
            arbitrationFee
        );

        disputeData = _disputeData;
        reservedChainIdForFork1 = ChainIdManager(chainIdManager)
            .getNextUsableChainId();
        reservedChainIdForFork2 = ChainIdManager(chainIdManager)
            .getNextUsableChainId();
        // solhint-disable-next-line not-rely-on-time
        executionTimeForProposal = (block.timestamp + forkPreparationTime);
    }

    /**
     * @dev function that executes a fork proposal
     */
    function executeFork() external onlyBeforeForking {
        if (
            executionTimeForProposal == 0 ||
            // solhint-disable-next-line not-rely-on-time
            executionTimeForProposal > block.timestamp
        ) {
            revert NotYetReadyToFork();
        }

        // Create the children of each contract
        NewInstances memory newInstances;
        (
            newInstances.forkingManager.one,
            newInstances.forkingManager.two
        ) = _createChildren();
        (newInstances.bridge.one, newInstances.bridge.two) = IForkableBridge(
            bridge
        ).createChildren();
        (newInstances.zkEVM.one, newInstances.zkEVM.two) = IForkableZkEVM(zkEVM)
            .createChildren();
        (
            newInstances.forkonomicToken.one,
            newInstances.forkonomicToken.two
        ) = IForkonomicToken(forkonomicToken).createChildren();
        (
            newInstances.globalExitRoot.one,
            newInstances.globalExitRoot.two
        ) = IForkableGlobalExitRoot(globalExitRoot).createChildren();

        // Initialize the zkEVM contracts
        IPolygonZkEVM.InitializePackedParameters
            memory initializePackedParameters;

        {
            // retrieve some information from the zkEVM contract
            bytes32 genesisRoot = IPolygonZkEVM(zkEVM).batchNumToStateRoot(
                IPolygonZkEVM(zkEVM).lastVerifiedBatch()
            );
            // the following variables could be used to save gas, but it requires via-ir in the compiler settings
            string memory trustedSequencerURL = IPolygonZkEVM(zkEVM)
                .trustedSequencerURL();
            string memory networkName = IPolygonZkEVM(zkEVM).networkName();
            initializePackedParameters = IPolygonZkEVM
                .InitializePackedParameters({
                    admin: IPolygonZkEVM(zkEVM).admin(),
                    trustedSequencer: IPolygonZkEVM(zkEVM).trustedSequencer(),
                    pendingStateTimeout: IPolygonZkEVM(zkEVM)
                        .pendingStateTimeout(),
                    trustedAggregator: IPolygonZkEVM(zkEVM).trustedAggregator(),
                    trustedAggregatorTimeout: IPolygonZkEVM(zkEVM)
                        .trustedAggregatorTimeout(),
                    chainID: reservedChainIdForFork1,
                    forkID: IPolygonZkEVM(zkEVM).forkID()
                });
            IForkableZkEVM(newInstances.zkEVM.one).initialize(
                newInstances.forkingManager.one,
                zkEVM,
                initializePackedParameters,
                genesisRoot,
                trustedSequencerURL,
                networkName,
                "0.1.0", // hardcoded as the version is not stored in the zkEVM contract, only emitted as event
                IPolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.one),
                IERC20Upgradeable(newInstances.forkonomicToken.one),
                IForkableZkEVM(zkEVM).rollupVerifier(),
                IPolygonZkEVMBridge(newInstances.bridge.one)
            );
            initializePackedParameters.chainID = reservedChainIdForFork2;
            IForkableZkEVM(newInstances.zkEVM.two).initialize(
                newInstances.forkingManager.two,
                zkEVM,
                initializePackedParameters,
                genesisRoot,
                trustedSequencerURL,
                networkName,
                "0.1.0", // hardcoded as the version is not stored in the zkEVM contract, only emitted as event
                IPolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.two),
                IERC20Upgradeable(newInstances.forkonomicToken.two),
                IForkableZkEVM(zkEVM).rollupVerifier(),
                IPolygonZkEVMBridge(newInstances.bridge.two)
            );
        }

        // Initialize the tokens
        IForkonomicToken(newInstances.forkonomicToken.one).initialize(
            newInstances.forkingManager.one,
            forkonomicToken,
            address(this),
            string.concat(IERC20Metadata(forkonomicToken).name(), "0"),
            IERC20Metadata(forkonomicToken).symbol()
        );
        IForkonomicToken(newInstances.forkonomicToken.two).initialize(
            newInstances.forkingManager.two,
            forkonomicToken,
            address(this),
            string.concat(IERC20Metadata(forkonomicToken).name(), "1"),
            IERC20Metadata(forkonomicToken).symbol()
        );

        bytes32[DEPOSIT_CONTRACT_TREE_DEPTH]
            memory depositBranch = IForkableBridge(bridge).getBranch();

        //Initialize the bridge contracts
        IForkableBridge(newInstances.bridge.one).initialize(
            newInstances.forkingManager.one,
            bridge,
            0, // network identifiers will always be 0 on mainnet and 1 on L2
            IBasePolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.one),
            address(newInstances.zkEVM.one),
            address(newInstances.forkonomicToken.one),
            false,
            IForkableBridge(bridge).getHardAssetManager(),
            IForkableBridge(bridge).getLastUpdatedDepositCount(),
            depositBranch
        );
        IForkableBridge(newInstances.bridge.two).initialize(
            newInstances.forkingManager.two,
            bridge,
            0,
            IBasePolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.two),
            address(newInstances.zkEVM.two),
            address(newInstances.forkonomicToken.two),
            false,
            IForkableBridge(bridge).getHardAssetManager(),
            IForkableBridge(bridge).getLastUpdatedDepositCount(),
            depositBranch
        );

        //Initialize the forking manager contracts
        IForkingManager(newInstances.forkingManager.one).initialize(
            newInstances.zkEVM.one,
            newInstances.bridge.one,
            newInstances.forkonomicToken.one,
            address(this),
            newInstances.globalExitRoot.one,
            arbitrationFee,
            chainIdManager,
            forkPreparationTime
        );
        IForkingManager(newInstances.forkingManager.two).initialize(
            newInstances.zkEVM.two,
            newInstances.bridge.two,
            newInstances.forkonomicToken.two,
            address(this),
            newInstances.globalExitRoot.two,
            arbitrationFee,
            chainIdManager,
            forkPreparationTime
        );

        //Initialize the global exit root contracts
        IForkableGlobalExitRoot(newInstances.globalExitRoot.one).initialize(
            newInstances.forkingManager.one,
            globalExitRoot,
            newInstances.zkEVM.one,
            newInstances.bridge.one,
            IForkableGlobalExitRoot(globalExitRoot).lastMainnetExitRoot(),
            IForkableGlobalExitRoot(globalExitRoot).lastRollupExitRoot()
        );
        IForkableGlobalExitRoot(newInstances.globalExitRoot.two).initialize(
            newInstances.forkingManager.two,
            globalExitRoot,
            newInstances.zkEVM.two,
            newInstances.bridge.two,
            IForkableGlobalExitRoot(globalExitRoot).lastMainnetExitRoot(),
            IForkableGlobalExitRoot(globalExitRoot).lastRollupExitRoot()
        );
    }
}
