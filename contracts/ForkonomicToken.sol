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
    /// 1st parameter: address The address of the token owner
    /// 2nd parameter: bool indicating whether the first or second child was burnt
    /// 3rd parameter: uint256 The amount of burned tokens
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
        if (!hasRole(MINTER_ROLE, msg.sender) && msg.sender != parentContract) {
            revert NotMinterRole();
        }
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

    /// @inheritdoc IForkonomicToken
    function splitTokenAndMintOneChild(
        uint256 amount,
        bool firstChild,
        bool useChildTokenAllowance
    ) public onlyAfterForking {
        if (useChildTokenAllowance) {
            if (childTokenAllowances[msg.sender][firstChild] < amount) {
                revert NotSufficientAllowance();
            }
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

    /// @inheritdoc IForkonomicToken
    function splitTokensIntoChildTokens(uint256 amount) external {
        splitTokenAndMintOneChild(amount, true, false);
        splitTokenAndMintOneChild(amount, false, true);
    }
}
