pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./mixin/ForkStructure.sol";
import "./interfaces/IForkonomicToken.sol";
import "./mixin/ForkableUUPS.sol";

contract ForkonomicToken is
    IForkonomicToken,
    ERC20PresetMinterPauser,
    ForkableUUPS,
    Initializable
{
    constructor() ERC20PresetMinterPauser("Forkonomic Token", "FORK") {}

    /// @inheritdoc IForkonomicToken
    function initialize(
        address _forkmanager,
        address _parentContract,
        address admin
    ) external override initializer {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
        _setupRole(DEFAULT_ADMIN_ROLE, admin);
        _setupRole(MINTER_ROLE, admin);
    }

    function splitTokensIntoChildTokens(uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        ERC20PresetMinterPauser(children[0]).mint(msg.sender, amount);
        ERC20PresetMinterPauser(children[1]).mint(msg.sender, amount);
    }

    function createChildren(
        address implementation
    ) external onlyForkManger returns (address, address) {
        return _createChildren(implementation);
    }
}
