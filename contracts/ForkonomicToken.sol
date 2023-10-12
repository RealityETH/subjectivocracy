// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";

contract ForkonomicToken is
    IForkonomicToken,
    ERC20Upgradeable,
    ForkableStructure,
    AccessControlUpgradeable
{
    /// @dev The role that allows minting new tokens
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @inheritdoc IForkonomicToken
    function initialize(
        address _forkmanager,
        address _parentContract,
        address minter,
        string calldata name,
        string calldata symbol
    ) external initializer {
        ForkableStructure.initialize(_forkmanager, _parentContract);
        _setupRole(MINTER_ROLE, minter);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        __ERC20_init(name, symbol);
    }

    /// @inheritdoc IForkonomicToken
    function mint(address to, uint256 amount) external {
        require(
            hasRole(MINTER_ROLE, msg.sender) || msg.sender == parentContract,
            "Caller is not a minter"
        );
        _mint(to, amount);
    }

    /// @inheritdoc IForkonomicToken
    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }

    /// @dev Allows anyone to split the tokens from the parent contract into the tokens of the children
    /// @param amount The amount of tokens to split
    function splitTokensIntoChildTokens(uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        IForkonomicToken(children[0]).mint(msg.sender, amount);
        IForkonomicToken(children[1]).mint(msg.sender, amount);
    }
}
