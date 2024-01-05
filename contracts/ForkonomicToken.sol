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

    /// @dev Mapping that stores burned amounts
    /// address The address of the token owner
    /// bool indicating whether the first or second child was burnt
    /// uint256 The amount of burned tokens
    mapping(address => mapping(bool => uint256)) public childTokenAllowances;

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
    function createChildren()
        external
        onlyForkManger
        returns (address, address)
    {
        return _createChildren();
    }

    function splitTokenAndMintOneChild(
        uint256 amount,
        bool firstChild,
        bool useChildTokenAllowance
    ) public onlyAfterForking {
        require(children[0] != address(0), "Children not created yet");
        if (useChildTokenAllowance) {
            require(
                childTokenAllowances[msg.sender][firstChild] >= amount,
                "Not enough allowance"
            );
            childTokenAllowances[msg.sender][firstChild] -= amount;
        } else {
            _burn(msg.sender, amount);
            childTokenAllowances[msg.sender][!firstChild] += amount;
        }
        IForkonomicToken(firstChild ? children[0] : children[1]).mint(
            msg.sender,
            amount
        );
    }

    /// @dev Allows anyone to prepare the splitting of tokens
    /// by burning them
    /// @param amount The amount of tokens to burn
    function prepareSplittingTokens(uint256 amount) public {
        require(children[0] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        childTokenAllowances[msg.sender][false] += amount;
        childTokenAllowances[msg.sender][true] += amount;
    }

    /// @dev Allows anyone to split the tokens from the parent contract into the tokens of the children
    /// @param amount The amount of tokens to split
    function splitTokensIntoChildTokens(uint256 amount) external {
        splitTokenAndMintOneChild(amount, true, false);
        splitTokenAndMintOneChild(amount, false, true);
    }
}
