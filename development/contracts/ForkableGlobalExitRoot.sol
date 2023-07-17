pragma solidity ^0.8.17;

import {PolygonZkEVMGlobalExitRoot} from "@RealityETH/zkevm-contracts/contracts/inheritedMainContracts/PolygonZkEVMGlobalExitRoot.sol";
import {TokenWrapped} from "@RealityETH/zkevm-contracts/contracts/lib/TokenWrapped.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import {ForkableUUPS} from "./mixin/ForkableUUPS.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {IForkableGlobalExitRoot} from "./interfaces/IForkableGlobalExitRoot.sol";

contract ForkableGlobalExitRoot is IForkableGlobalExitRoot, ForkableUUPS, PolygonZkEVMGlobalExitRoot {
    /// @dev Initializting function
    /// @param _forkmanager The address of the forkmanager
    /// @param _parentContract The address of the parent contract
    /// @param _rollupAddress The address of the rollup contract
    /// @param _bridgeAddress The address of the bridge contract
    function initialize(
        address _forkmanager,
        address _parentContract,
        address _rollupAddress,
        address _bridgeAddress
    ) public initializer {
        ForkableUUPS.initialize(_forkmanager, _parentContract, msg.sender);
        PolygonZkEVMGlobalExitRoot.initialize(_rollupAddress, _bridgeAddress);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /// @dev Overrites the other initialize functions from ForkableStructure and PolygonZkEVMGlobalExitRoot
    /// @notice If we would not do it, it would throw the following error:
    /// "Derived contract must override function "initialize". Two or more base classes
    /// define function with same name and parameter types."
    function initialize(
        address forkmanager,
        address parentContract
    )
        public
        virtual
        override(ForkableStructure, PolygonZkEVMGlobalExitRoot)
        onlyInitializing
    {
        revert(
            string(
                abi.encode(
                    "illicit call to initialize with arguments:",
                    forkmanager,
                    parentContract
                )
            )
        );
    }

    /// @dev Public interface to create children. This can only be done by the forkmanager
    /// @param implementation Allows to pass a different implementation contract for the second proxied child.
    /// @return The addresses of the two children
    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }
}
