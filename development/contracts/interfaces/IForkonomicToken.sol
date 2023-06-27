pragma solidity ^0.8.17;

import "./IForkableStructure.sol";

interface IForkonomicToken is IForkableStructure {
    /**
     * @notice Allows the forkmanager to initialize the contract
     * @param _forkmanager The address of the forkmanager
     * @param _parentContract The address of the parent contract
     */
    function initialize(address _forkmanager, address _parentContract) external;

    function createChildren(
        address implementation
    ) external returns (address, address);
}
