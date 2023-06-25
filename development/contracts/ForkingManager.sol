pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@RealityETH/zkevm-contracts/contracts/interfaces/IPolygonZkEVM.sol";
import "./interfaces/IForkableBridge.sol";
import "./interfaces/IForkableZkEVM.sol";
import "./interfaces/IForkingManager.sol";
import "./interfaces/IForkonomicToken.sol";
import "./mixin/ForkStructure.sol";

contract ForkingManager is IForkingManager, ForkStructure, Initializable {
    using SafeERC20 for IERC20;
    address public zkEVM;
    address public bridge;
    address public forkonomicToken;
    uint256 public arbitrationFee;
    address public disputeContract;
    bytes public disputeCall;

    /// @inheritdoc IForkingManager
    function initialize(
        address _zkEVM,
        address _bridge,
        address _forkonomicToken,
        address _parentContract,
        uint256 _arbitrationFee
    ) external initializer {
        zkEVM = _zkEVM;
        bridge = _bridge;
        forkonomicToken = _forkonomicToken;
        parentContract = _parentContract;
        arbitrationFee = _arbitrationFee;
    }

    function createChildren(address implementation) internal returns(address,  address) {
        address forkingManager1 = ClonesUpgradeable.clone(implementation);
        children[0] = forkingManager1;
        address forkingManager2 = ClonesUpgradeable.clone(implementation);
        children[1] = forkingManager2;
        return (children[0], children[1]);
    }

    function getChainID() public view returns (uint32) {
        uint256 id;
        assembly {
            id := chainid()
        }
        return uint32(id);
    }

    function initiateFork(address _disputeContract, bytes memory _disputeCall) external {
        require(children[0] == address(0), "Children already created");
        require(children[1] == address(0), "Children already created");
        // Charge the forking fee
        IERC20(forkonomicToken).safeTransferFrom(msg.sender, address(this), arbitrationFee);

        // Create the children of each contract
        (address forkmanager1, address forkmanager2) = createChildren(address(this));
        (address token1, address token2) = IForkonomicToken(forkonomicToken).createChildren();
        (address bridge1, address bridge2) = IForkableBridge(bridge).createChildren();
        (address zkevm1, address zkevm2) = IForkableZkEVM(zkEVM).createChildren();

        // retrieve some information from the zkEVM contract
        bytes32 genesisRoot = IPolygonZkEVM(zkEVM).batchNumToStateRoot(IPolygonZkEVM(zkEVM).lastVerifiedBatch());
        string memory _trustedSequencerURL = IPolygonZkEVM(zkEVM).trustedSequencerURL();
        string memory _networkName = IPolygonZkEVM(zkEVM).networkName();
        string memory _version = "0.1.0"; // Todo: get version from zkEVM, currently only emitted as event
        IPolygonZkEVMGlobalExitRoot _globalExitRootManager = IPolygonZkEVM(zkEVM).globalExitRootManager();
        IERC20Upgradeable _matic = IERC20Upgradeable(token1);
        IVerifierRollup _rollupVerifier = IForkableZkEVM(zkEVM).rollupVerifier();
        IPolygonZkEVMBridge _bridgeAddress = IPolygonZkEVMBridge(bridge1);
        IPolygonZkEVM.InitializePackedParameters memory initializePackedParameters = IPolygonZkEVM.InitializePackedParameters ({
         admin: IPolygonZkEVM(zkEVM).admin(),
         trustedSequencer: IPolygonZkEVM(zkEVM).trustedSequencer(),
         pendingStateTimeout: IPolygonZkEVM(zkEVM).pendingStateTimeout(),
         trustedAggregator:  IPolygonZkEVM(zkEVM).trustedAggregator(),
         trustedAggregatorTimeout:  IPolygonZkEVM(zkEVM).trustedAggregatorTimeout()
        });

        // Initialize the tokens
        IForkonomicToken(token1).initialize(forkmanager1, forkonomicToken);
        IForkonomicToken(token2).initialize(forkmanager2, forkonomicToken);

        //Initialize the zkevm contracts
        uint64 _chainID = IPolygonZkEVM(zkEVM).chainID() / 2 * 2 + 3;
        uint64 _forkID = IPolygonZkEVM(zkEVM).forkID() / 2 * 2 + 3;
        IForkableZkEVM(zkevm1).initialize(forkmanager1, zkEVM, initializePackedParameters, genesisRoot, _trustedSequencerURL, _networkName, _version, _globalExitRootManager, _matic, _rollupVerifier, _bridgeAddress, _chainID, _forkID);
        _chainID +=1 ;
        _forkID += 1;
        _bridgeAddress = IPolygonZkEVMBridge(bridge2);
        _matic = IERC20Upgradeable(token2);
        IForkableZkEVM(zkevm2).initialize(forkmanager2, zkEVM, initializePackedParameters, genesisRoot, _trustedSequencerURL, _networkName, _version, _globalExitRootManager, _matic, _rollupVerifier, _bridgeAddress, _chainID, _forkID);
        
        //Initialize the bridge contracts
        IForkableBridge(bridge1).initialize(forkmanager1, bridge, getChainID(), _globalExitRootManager, address(zkevm1), address(token1), false);
        IForkableBridge(bridge2).initialize(forkmanager2, bridge, getChainID(), _globalExitRootManager, address(zkevm2), address(token2), false);
        
        //Initialize the forking manager contracts
        IForkingManager(forkmanager1).initialize(zkevm1, bridge1, token1, address(this), arbitrationFee);
        IForkingManager(forkmanager2).initialize(zkevm2, bridge2, token2, address(this), arbitrationFee);

        // Store the dispute contract and call to identify the dispute
        disputeContract = _disputeContract;
        disputeCall = _disputeCall;
    }

    
}