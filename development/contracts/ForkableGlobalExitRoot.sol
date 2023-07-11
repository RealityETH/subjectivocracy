pragma solidity ^0.8.17;

import "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMGlobalExitRoot.sol";
import "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "./interfaces/IForkableZkEVM.sol";
import "./mixin/ForkableUUPS.sol";

contract ForkableGlobalExitRoot is ForkableUUPS, PolygonZkEVMGlobalExitRoot {

    function initialize(
        address _forkmanager,
        address _parentContract,
        address _rollupAddress,
        address _bridgeAddress
    ) public initializer {
        ForkableUUPS.initialize( _forkmanager, _parentContract);
        PolygonZkEVMGlobalExitRoot.initialize(_rollupAddress, _bridgeAddress);
        _setupRole(UPDATER, msg.sender);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    function initialize(address _forkmanager, address _parentContract) public virtual override(ForkableUUPS,PolygonZkEVMGlobalExitRoot ) onlyInitializing {
        revert();
    }

    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }
}
