pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ForknomicToken is ERC20PresetMinterPauser, Initializable {
    address public forkmanager;
    address public parentToken;
    address[] public children = new address[](2);

    modifier onlyParent() {
        require(msg.sender == parentToken);
        _;
    }

    modifier onlyForkManger() {
        require(msg.sender == forkmanager);
        _;
    }

    constructor() ERC20PresetMinterPauser("Forkonomic Token", "FORK") {}

    function initialize(
        address _forkmanager,
        address _parentToken
    ) external initializer {
        forkmanager = _forkmanager;
        parentToken = _parentToken;
    }

    /**
     * @notice Allows the forkmanager to create the new children
     */
    function createChildren() external onlyForkManger {
        address forkableToken = ClonesUpgradeable.clone(address(this));
        // Todo: forkableToken.initialize
        children[0] = forkableToken;
        forkableToken = ClonesUpgradeable.clone(address(this));
        // Todo: forkableToken.initialize
        children[1] = forkableToken;
    }

    function getChild(uint256 index) external view returns (address) {
        return children[index];
    }

    function splitTokensIntoChildTokens(uint256 amount) external {
        require(children[0] != address(0), "Children not created yet");
        require(children[1] != address(0), "Children not created yet");
        _burn(msg.sender, amount);
        ERC20PresetMinterPauser(children[0]).mint(msg.sender, amount);
        ERC20PresetMinterPauser(children[1]).mint(msg.sender, amount);
    }
}
