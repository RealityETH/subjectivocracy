pragma solidity ^0.8.17;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ForkableStructure} from "./mixin/ForkableStructure.sol";
import {IForkonomicToken} from "./interfaces/IForkonomicToken.sol";
import {ForkableUUPS} from "./mixin/ForkableUUPS.sol";

contract ForkonomicToken is IForkonomicToken, ERC20Upgradeable, ForkableUUPS {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    function mint(address to, uint256 amount) external {
        require(hasRole(MINTER_ROLE, msg.sender), "Caller is not a minter");
        _mint(to, amount);
    }

    /// @inheritdoc IForkonomicToken
    function initialize(
        address _forkmanager,
        address _parentContract,
        address minter,
        string calldata name,
        string calldata symbol
    ) external initializer {
        ForkableUUPS.initialize(_forkmanager, _parentContract, msg.sender);
        _setupRole(MINTER_ROLE, minter);
        _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
        __ERC20_init(name, symbol);
    }

    function splitTokensIntoChildTokens(uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        IForkonomicToken(children[0]).mint(msg.sender, amount);
        IForkonomicToken(children[1]).mint(msg.sender, amount);
    }

    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }
}