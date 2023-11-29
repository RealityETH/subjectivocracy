// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {IForkableStructure} from "./IForkableStructure.sol";
import {IERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";

interface IForkonomicToken is IForkableStructure, IERC20Upgradeable {
    /**
     * @notice Allows the forkmanager to initialize the contract
     * @param _forkmanager The address of the forkmanager
     * @param _parentContract The address of the parent contract
     * @param admin The address of the admin of erc20 token
     */
    function initialize(
        address _forkmanager,
        address _parentContract,
        address admin,
        string calldata name,
        string calldata symbol
    ) external;

    /// @dev Allows the parent contract to mint new tokens
    /// @param to The address of the receiver
    /// @param amount The amount of tokens to mint
    function mint(address to, uint256 amount) external;

    /// @dev Interface for the forkManger to create children
    /// @param implementation Allows to pass a different implementation contract for the second proxied child.
    /// @return The addresses of the two children
    function createChildren(
        address implementation
    ) external returns (address, address);

    /// @dev Allows anyone to split the tokens from the parent contract into the tokens of the children
    /// @param amount The amount of tokens to split
    function splitTokensIntoChildTokens(uint256 amount) external;

    /// @dev Allows anyone to split the tokens from the parent contract into the tokens of the children
    /// @param amount The amount of tokens to split
    /// @param firstChild Whether to mint the first or second child
    /// @param useChildTokenAllowance Whether to use the child token allowance or the parent token balance
    function splitTokenAndMintOneChild(
        uint256 amount,
        bool firstChild,
        bool useChildTokenAllowance
    ) external;
}
