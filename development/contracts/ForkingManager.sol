pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import "./mixin/ForkableUUPS.sol";
import "./interfaces/IForkableBridge.sol";
import "./interfaces/IForkableZkEVM.sol";
import "./interfaces/IForkingManager.sol";
import "./interfaces/IForkonomicToken.sol";
import "./interfaces/IForkableGlobalExitRoot.sol";

contract ForkingManager is IForkingManager, ForkableUUPS {
    using SafeERC20 for IERC20;

    address public zkEVM;
    address public bridge;
    address public forkonomicToken;
    address public globalExitRoot;
    uint256 public arbitrationFee;
    address public disputeContract;
    bytes public disputeCall;

    /// @inheritdoc IForkingManager
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        address _globalExitRoot,
        uint256 _arbitrationFee
    ) external initializer {
        zkEVM = _zkEVM;
        bridge = _bridge;
        forkonomicToken = _forkonomicToken;
        parentContract = _parentContract;
        globalExitRoot = _globalExitRoot;
        arbitrationFee = _arbitrationFee;

        _setupRole(UPDATER, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    // todo: remove this function
    function getChainID() public view returns (uint32) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return uint32(id);
    }

    struct NewImplementations {
        address bridgeImplementation;
        address zkEVMImplementation;
        address forkonomicTokenImplementation;
        address forkingManagerImplementation;
        address globalExitRootImplementation;
    }

    struct AddressPair {
        address one;
        address two;
    }

    struct NewInstances {
        AddressPair forkingManager;
        AddressPair bridge;
        AddressPair zkEVM;
        AddressPair forkonomicToken;
        AddressPair globalExitRoot;
    }

    function initiateFork(
        address _disputeContract,
        bytes calldata _disputeCall,
        NewImplementations calldata newImplementations
    ) external {
        require(children[0] == address(0), "Children already created");
        require(children[1] == address(0), "Children already created");
        // Charge the forking fee
        IERC20(forkonomicToken).safeTransferFrom(msg.sender, address(this), arbitrationFee);
        // Create the children of each contract
        NewInstances memory newInstances;
        (newInstances.forkingManager.one, newInstances.forkingManager.two) =
            _createChildren(newImplementations.forkingManagerImplementation);
        (newInstances.bridge.one, newInstances.bridge.two) =
            IForkableBridge(bridge).createChildren(newImplementations.bridgeImplementation);
        (newInstances.zkEVM.one, newInstances.zkEVM.two) =
            IForkableZkEVM(zkEVM).createChildren(newImplementations.zkEVMImplementation);
        (newInstances.forkonomicToken.one, newInstances.forkonomicToken.two) =
            IForkonomicToken(forkonomicToken).createChildren(newImplementations.forkonomicTokenImplementation);
        (newInstances.globalExitRoot.one, newInstances.globalExitRoot.two) =
            IForkableGlobalExitRoot(globalExitRoot).createChildren(newImplementations.globalExitRootImplementation);

        IPolygonZkEVM.InitializePackedParameters memory initializePackedParameters;

        {
            // retrieve some information from the zkEVM contract
            bytes32 genesisRoot = IPolygonZkEVM(zkEVM).batchNumToStateRoot(IPolygonZkEVM(zkEVM).lastVerifiedBatch());
            IVerifierRollup _rollupVerifier = IForkableZkEVM(zkEVM).rollupVerifier();
            // the following variables could be used to save gas, but it requires via-ir in the compiler settings
            // string memory _trustedSequencerURL = IPolygonZkEVM(zkEVM)
            //     .trustedSequencerURL();
            // string memory _networkName = IPolygonZkEVM(zkEVM).networkName();
            // string memory _version = "0.1.0"; // Todo: get version from zkEVM, currently only emitted as event
            // IERC20Upgradeable _matic = IERC20Upgradeable(newInstances.forkonomicToken.one);
            // string memory _version = "0.1.0"; // Todo: get version from zkEVM, currently only emitted as event
            initializePackedParameters = IPolygonZkEVM.InitializePackedParameters({
                admin: IPolygonZkEVM(zkEVM).admin(),
                trustedSequencer: IPolygonZkEVM(zkEVM).trustedSequencer(),
                pendingStateTimeout: IPolygonZkEVM(zkEVM).pendingStateTimeout(),
                trustedAggregator: IPolygonZkEVM(zkEVM).trustedAggregator(),
                trustedAggregatorTimeout: IPolygonZkEVM(zkEVM).trustedAggregatorTimeout(),
                chainID: (IPolygonZkEVM(zkEVM).chainID() / 2) * 2 + 3,
                forkID: (IPolygonZkEVM(zkEVM).chainID() / 2) * 2 + 3
            });
            IForkableZkEVM(newInstances.zkEVM.one).initialize(
                newInstances.forkingManager.one,
                zkEVM,
                initializePackedParameters,
                genesisRoot,
                IPolygonZkEVM(zkEVM).trustedSequencerURL(),
                IPolygonZkEVM(zkEVM).networkName(),
                "0.1.0",
                IPolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.one),
                IERC20Upgradeable(newInstances.forkonomicToken.one),
                _rollupVerifier,
                IPolygonZkEVMBridge(newInstances.bridge.one)
            );
            initializePackedParameters.chainID += 1;
            initializePackedParameters.forkID += 1;
            IForkableZkEVM(newInstances.zkEVM.two).initialize(
                newInstances.forkingManager.two,
                zkEVM,
                initializePackedParameters,
                genesisRoot,
                IPolygonZkEVM(zkEVM).trustedSequencerURL(),
                IPolygonZkEVM(zkEVM).networkName(),
                "0.1.0",
                IPolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.two),
                IERC20Upgradeable(newInstances.forkonomicToken.two),
                _rollupVerifier,
                IPolygonZkEVMBridge(newInstances.bridge.two)
            );
        }

        // Initialize the tokens
        IForkonomicToken(newInstances.forkonomicToken.one).initialize(
            newInstances.forkingManager.one, forkonomicToken, address(this), string.concat(IERC20Metadata(forkonomicToken).name(), "0"), IERC20Metadata(forkonomicToken).symbol()
        );
        IForkonomicToken(newInstances.forkonomicToken.two).initialize(
            newInstances.forkingManager.two, forkonomicToken, address(this), string.concat(IERC20Metadata(forkonomicToken).name(), "1"), IERC20Metadata(forkonomicToken).symbol()
        );

        //Initialize the bridge contracts
        IForkableBridge(newInstances.bridge.one).initialize(
            newInstances.forkingManager.one,
            bridge,
            getChainID(),
            IBasePolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.one),
            address(newInstances.zkEVM.two),
            address(newInstances.forkonomicToken.one),
            false
        );
        IForkableBridge(newInstances.bridge.two).initialize(
            newInstances.forkingManager.two,
            bridge,
            getChainID(),
            IBasePolygonZkEVMGlobalExitRoot(newInstances.globalExitRoot.two),
            address(newInstances.zkEVM.two),
            address(newInstances.forkonomicToken.two),
            false
        );

        //Initialize the forking manager contracts
        IForkingManager(newInstances.forkingManager.one).initialize(
            newInstances.zkEVM.one,
            newInstances.bridge.one,
            newInstances.forkonomicToken.one,
            newInstances.globalExitRoot.one,
            address(this),
            arbitrationFee
        );
        IForkingManager(newInstances.forkingManager.two).initialize(
            newInstances.zkEVM.two,
            newInstances.zkEVM.two,
            newInstances.forkonomicToken.two,
            newInstances.globalExitRoot.two,
            address(this),
            arbitrationFee
        );

        // Store the dispute contract and call to identify the dispute
        disputeContract = _disputeContract;
        disputeCall = _disputeCall;
    }
}
