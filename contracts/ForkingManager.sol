// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {IPolygonZkEVM} from "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import {IVerifierRollup} from "@RealityETH/zkevm-contracts/contracts/interfaces/IVerifierRollup.sol";
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
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract ForkingManager is IForkingManager, ForkableStructure {
    struct DeploymentConfig {
        bytes32 genesisRoot;
        string trustedSequencerURL;
        string networkName;
        string version;
        IVerifierRollup rollupVerifier;
        address minter;
        string tokenName;
        string tokenSymbol;
        uint256 arbitrationFee;
        address chainIdManager;
        uint256 forkPreparationTime;
        address hardAssetManager;
        uint32 lastUpdatedDepositCount; // starts at 0
        bytes32 lastMainnetExitRoot;
        bytes32 lastRollupExitRoot;
        address parentGlobalExitRoot;
        address parentZkEVM;
        address parentForkonomicToken;
        address parentBridge;
    }

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

    // This can be called against the initial ForkingManager implementation to spawn a ForkingManager instance and all the other contracts involved
    function spawnInstance(
        address _admin,
        address _zkEVMImplementation,
        address _bridgeImplementation,
        address _forkonomicTokenImplementation,
        address _globalExitRootImplementation,
        DeploymentConfig memory _deploymentConfig,
        IPolygonZkEVM.InitializePackedParameters
            memory _initializePackedParameters
    ) external returns (address) {
        NewInstance memory instance = NewInstance(
            address(
                new TransparentUpgradeableProxy(
                    _zkEVMImplementation,
                    _admin,
                    ""
                )
            ),
            address(
                new TransparentUpgradeableProxy(
                    _bridgeImplementation,
                    _admin,
                    ""
                )
            ),
            address(
                new TransparentUpgradeableProxy(
                    _forkonomicTokenImplementation,
                    _admin,
                    ""
                )
            ),
            address(
                new TransparentUpgradeableProxy(
                    _globalExitRootImplementation,
                    _admin,
                    ""
                )
            ),
            address(new TransparentUpgradeableProxy(address(this), _admin, ""))
        );
        _initializeStack(
            instance,
            _deploymentConfig,
            _initializePackedParameters
        );
        return instance.forkingManager;
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

    function _prepareInitializePackedParameters(
        uint64 _newChainId
    ) internal view returns (IPolygonZkEVM.InitializePackedParameters memory) {
        return
            IPolygonZkEVM.InitializePackedParameters({
                admin: IPolygonZkEVM(zkEVM).admin(),
                trustedSequencer: IPolygonZkEVM(zkEVM).trustedSequencer(),
                pendingStateTimeout: IPolygonZkEVM(zkEVM).pendingStateTimeout(),
                trustedAggregator: IPolygonZkEVM(zkEVM).trustedAggregator(),
                trustedAggregatorTimeout: IPolygonZkEVM(zkEVM)
                    .trustedAggregatorTimeout(),
                chainID: _newChainId,
                forkID: IPolygonZkEVM(zkEVM).forkID(),
                lastVerifiedBatch: IPolygonZkEVM(zkEVM).lastVerifiedBatch()
            });
    }

    function _initializeStack(
        NewInstance memory _newInstance,
        DeploymentConfig memory _deploymentConfig,
        IPolygonZkEVM.InitializePackedParameters
            memory initializePackedParameters
    ) internal {
        {
            IForkableZkEVM(_newInstance.zkEVM).initialize(
                _newInstance.forkingManager,
                _deploymentConfig.parentZkEVM,
                initializePackedParameters,
                _deploymentConfig.genesisRoot,
                _deploymentConfig.trustedSequencerURL,
                _deploymentConfig.networkName,
                _deploymentConfig.version,
                IPolygonZkEVMGlobalExitRoot(_newInstance.globalExitRoot),
                IERC20Upgradeable(_newInstance.forkonomicToken),
                _deploymentConfig.rollupVerifier,
                IPolygonZkEVMBridge(_newInstance.bridge)
            );
        }

        // Initialize the tokens
        IForkonomicToken(_newInstance.forkonomicToken).initialize(
            _newInstance.forkingManager,
            _deploymentConfig.parentForkonomicToken,
            _deploymentConfig.minter, // TODO should this just be the parent token?
            _deploymentConfig.tokenName,
            _deploymentConfig.tokenSymbol
        );

        bytes32[DEPOSIT_CONTRACT_TREE_DEPTH] memory depositBranch;
        if (address(bridge) != address(0)) {
            depositBranch = IForkableBridge(bridge).getBranch();
        }

        //Initialize the bridge contracts
        IForkableBridge(_newInstance.bridge).initialize(
            _newInstance.forkingManager,
            _deploymentConfig.parentBridge,
            0, // network identifiers will always be 0 on mainnet and 1 on L2
            IBasePolygonZkEVMGlobalExitRoot(_newInstance.globalExitRoot),
            address(_newInstance.zkEVM),
            address(_newInstance.forkonomicToken),
            false,
            _deploymentConfig.hardAssetManager,
            _deploymentConfig.lastUpdatedDepositCount,
            depositBranch
        );

        //Initialize the forking manager contracts
        IForkingManager(_newInstance.forkingManager).initialize(
            _newInstance.zkEVM,
            _newInstance.bridge,
            _newInstance.forkonomicToken,
            address(this), // TODO check this
            _newInstance.globalExitRoot,
            _deploymentConfig.arbitrationFee,
            _deploymentConfig.chainIdManager,
            _deploymentConfig.forkPreparationTime
        );

        //Initialize the global exit root contracts
        IForkableGlobalExitRoot(_newInstance.globalExitRoot).initialize(
            _newInstance.forkingManager,
            _deploymentConfig.parentGlobalExitRoot,
            _newInstance.zkEVM,
            _newInstance.bridge,
            _deploymentConfig.lastMainnetExitRoot,
            _deploymentConfig.lastRollupExitRoot
        );
    }

    /**
     * @dev Clones the current deployment ready to configure a child in a fork
     */
    function _cloneDeploymentConfig()
        internal
        returns (DeploymentConfig memory)
    {
        return
            DeploymentConfig({
                genesisRoot: IPolygonZkEVM(zkEVM).batchNumToStateRoot(
                    IPolygonZkEVM(zkEVM).lastVerifiedBatch()
                ),
                trustedSequencerURL: IPolygonZkEVM(zkEVM).trustedSequencerURL(),
                networkName: IPolygonZkEVM(zkEVM).networkName(),
                version: "0.0.1", // hardcoded as the version is not stored in the zkEVM contract, only emitted as event
                rollupVerifier: IForkableZkEVM(zkEVM).rollupVerifier(),
                minter: address(0), // We only mint against genesis
                tokenName: string.concat(
                    IERC20Metadata(forkonomicToken).name(),
                    "0"
                ),
                tokenSymbol: IERC20Metadata(forkonomicToken).symbol(),
                arbitrationFee: arbitrationFee,
                chainIdManager: chainIdManager,
                forkPreparationTime: forkPreparationTime,
                hardAssetManager: IForkableBridge(bridge).getHardAssetManager(),
                lastUpdatedDepositCount: IForkableBridge(bridge)
                    .getLastUpdatedDepositCount(),
                lastMainnetExitRoot: IForkableGlobalExitRoot(globalExitRoot)
                    .lastMainnetExitRoot(),
                lastRollupExitRoot: IForkableGlobalExitRoot(globalExitRoot)
                    .lastRollupExitRoot(),
                parentGlobalExitRoot: globalExitRoot,
                parentZkEVM: zkEVM,
                parentForkonomicToken: forkonomicToken,
                parentBridge: bridge
            });
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

        (address forkingManager1, address forkingManager2) = _createChildren();

        (address bridge1, address bridge2) = IForkableBridge(bridge)
            .createChildren();

        (address zkEVM1, address zkEVM2) = IForkableZkEVM(zkEVM)
            .createChildren();

        (address forkonomicToken1, address forkonomicToken2) = IForkonomicToken(
            forkonomicToken
        ).createChildren();

        (
            address globalExitRoot1,
            address globalExitRoot2
        ) = IForkableGlobalExitRoot(globalExitRoot).createChildren();

        NewInstance memory child1 = NewInstance(
            zkEVM1,
            bridge1,
            forkonomicToken1,
            globalExitRoot1,
            forkingManager1
        );

        NewInstance memory child2 = NewInstance(
            zkEVM2,
            bridge2,
            forkonomicToken2,
            globalExitRoot2,
            forkingManager2
        );

        DeploymentConfig memory deploymentConfig = _cloneDeploymentConfig();

        _initializeStack(
            child1,
            deploymentConfig,
            _prepareInitializePackedParameters(reservedChainIdForFork1)
        );
        _initializeStack(
            child2,
            deploymentConfig,
            _prepareInitializePackedParameters(reservedChainIdForFork2)
        );
    }
}
