pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./mixin/ForkStructure.sol";
import "./interfaces/IForkonomicToken.sol";

contract ForknomicToken is
    IForkonomicToken,
    ERC20PresetMinterPauser,
    Initializable,
    ForkStructure
{
    constructor() ERC20PresetMinterPauser("Forkonomic Token", "FORK") {}

    /// @inheritdoc IForkonomicToken
    function initialize(
        address _forkmanager,
        address _parentContract
    ) external override initializer {
        forkmanager = _forkmanager;
        parentContract = _parentContract;
    }

    /// @inheritdoc IForkonomicToken
    function createChildren()
        external
        override
        onlyForkManger
        returns (address, address)
    {
        address forkableToken = ClonesUpgradeable.clone(address(this));
        children[0] = forkableToken;
        forkableToken = ClonesUpgradeable.clone(address(this));
        children[1] = forkableToken;
        return (children[0], children[1]);
    }

    function splitTokensIntoChildTokens(uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        ERC20PresetMinterPauser(children[0]).mint(msg.sender, amount);
        ERC20PresetMinterPauser(children[1]).mint(msg.sender, amount);
    }
}
