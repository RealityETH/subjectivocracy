// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.17;

import {StorageSlot} from "@openzeppelin/contracts/utils/StorageSlot.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

library CreateChildren {
    /**
     * @dev Storage slot with the address of the current implementation.
     * This is the keccak-256 hash of "eip1967.proxy.implementation" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    /**
     * @dev Returns the current implementation address.
     */
    function _getImplementation() internal view returns (address) {
        return StorageSlot.getAddressSlot(_IMPLEMENTATION_SLOT).value;
    }

    /**
     * @dev Storage slot with the admin of the contract.
     * This is the keccak-256 hash of "eip1967.proxy.admin" subtracted by 1, and is
     * validated in the constructor.
     */
    bytes32 internal constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    /**
     * @dev Returns the current admin.
     */
    function _getAdmin() internal view returns (address) {
        return StorageSlot.getAddressSlot(_ADMIN_SLOT).value;
    }

    /// @dev Internal function to create the children contracts.
    ///
    /// @param implementation Allows to pass a different implementation contract for the second proxied child.
    function createChildren(
        address implementation
    ) public returns (address forkingManager1, address forkingManager2) {
        // Fork 1 will always keep the original implementation
        forkingManager1 = address(
            new TransparentUpgradeableProxy(
                _getImplementation(),
                _getAdmin(),
                ""
            )
        );
        // Fork 2 can introduce a new implementation, if a different implementation contract
        // is passed in
        forkingManager2 = address(
            new TransparentUpgradeableProxy(implementation, _getAdmin(), "")
        );
    }
}
