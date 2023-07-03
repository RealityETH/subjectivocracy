pragma solidity ^0.8.17;

import "./IForkableStructure.sol";

interface IForkonomicToken is IForkableStructure {
    /**
     * @notice Allows the forkmanager to initialize the contract
     * @param _forkmanager The address of the forkmanager
     * @param _parentContract The address of the parent contract
     * @param admin The address of the admin of erc20 token
     */
    function initialize(
        address _forkmanager,
        address _parentContract,
        address admin
    ) external;

    function createChildren(
        address implementation
    ) external returns (address, address);
}
