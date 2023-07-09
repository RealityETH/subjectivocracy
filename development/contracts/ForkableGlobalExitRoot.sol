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
    ) external initializer {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
        PolygonZkEVMGlobalExitRoot.initialize(_rollupAddress, _bridgeAddress);
    }

    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }
}
