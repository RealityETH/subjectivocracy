pragma solidity ^0.8.17;

import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ForkableStructure} from "./ForkableStructure.sol";

abstract contract ForkableUUPS is
    ForkableStructure,
    UUPSUpgradeable,
    AccessControlUpgradeable
{
    /// @dev The following role is allowed to trigger the upgrade of the implementation contract
    bytes32 public constant UPDATER = keccak256("UPDATER");

    function initialize(
        address _forkmanager,
        address _parentContract,
        address _updater
    ) public virtual onlyInitializing {
        ForkableStructure.initialize(_forkmanager, _parentContract);
        _setupRole(UPDATER, _updater);
    }

    /// @dev The _authorizeUpgrade is overriding the abstract function from UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        require(hasRole(UPDATER, msg.sender), "Caller is not an updater");
    }

    /// @dev Internal function to create the children contracts.
    ///
    /// @param implementation Allows to pass a different implementation contract for the second proxied child.
    function _createChildren(
        address implementation
    ) internal returns (address forkingManager1, address forkingManager2) {
        // Fork 1 will always keep the original implementation
        forkingManager1 = address(new ERC1967Proxy(_getImplementation(), ""));
        children[0] = forkingManager1;
        // Fork 2 can introduce a new implementation, if a different implementation contract
        // is passed in
        forkingManager2 = address(new ERC1967Proxy(implementation, ""));
        children[1] = forkingManager2;
    }
}
