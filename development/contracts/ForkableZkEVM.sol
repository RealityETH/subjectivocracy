pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/PolygonZkEVM.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";

contract ForkableZkEVM is PolygonZkEVM {
    address public forkmanager;
    address public parentZkEVM;
    address[] public children = new address[](2);

    modifier onlyParent() {
        require(msg.sender == parentZkEVM);
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager);
        _;
    }

    // probably the constructor needs to be rewritten and merged with initializer
    /**
     * @param _globalExitRootManager Global exit root manager address
     * @param _matic MATIC token address
     * @param _rollupVerifier Rollup verifier address
     * @param _bridgeAddress Bridge address
     * @param _chainID L2 chainID
     * @param _forkID Fork Id
     */
    constructor(
        IPolygonZkEVMGlobalExitRoot _globalExitRootManager,
        IERC20Upgradeable _matic,
        IVerifierRollup _rollupVerifier,
        IPolygonZkEVMBridge _bridgeAddress,
        uint64 _chainID,
        uint64 _forkID
    )
        PolygonZkEVM(
            _globalExitRootManager,
            _matic,
            _rollupVerifier,
            _bridgeAddress,
            _chainID,
            _forkID
        )
    {}

    function initialize(
        address _forkmanager,
        address _parentZkEVM
    ) external initializer {
        forkmanager = _forkmanager;
        parentZkEVM = _parentZkEVM;
        // todo: overwrite the initialization once interfaces are correct.
        // PolygonZkEVMBridge.initialize
    }

    /**
     * @notice Allows the forkmanager to create the new children
     */
    function createChildren() external onlyForkManger {
        // create emergency mode to stop all operations:
        _activateEmergencyState();
        address forkableZkEVM = ClonesUpgradeable.clone(address(this));
        // Todo: forkableZkEVM.initialize
        children[0] = forkableZkEVM;
        forkableZkEVM = ClonesUpgradeable.clone(address(this));
        // Todo: forkableZkEVM.initialize
        children[1] = forkableZkEVM;
    }

    function getChild(uint256 index) external view returns (address) {
        return children[index];
    }
}
