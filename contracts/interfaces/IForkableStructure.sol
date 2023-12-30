// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.20;

interface IForkableStructure {
    /// @dev Error thrown when trying to call a function that can only be called after forking
    error NoChangesAfterForking();
    /// @dev Error thrown when trying to call a function that can only be called before forking
    error OnlyAfterForking();
    /// @dev Error thrown when trying to call a function that can only be called by the parent contract
    error OnlyParentIsAllowed();
    /// @dev Error thrown when trying to call a function that can only be called by the forkmanager
    error OnlyForkManagerIsAllowed();

    /// @dev Returns the address of the forkmanager
    function forkmanager() external view returns (address);

    /// @dev Returns the address of the parent contract
    function parentContract() external view returns (address);

    /// @dev Returns the addresses of the two children
    function getChildren() external view returns (address, address);
}
