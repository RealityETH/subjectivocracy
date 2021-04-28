pragma solidity ^0.4.25;

import './IERC20.sol';
import './IRealitio.sol';
import './BridgeToL2.sol';

contract IForkManager is IERC20 {

    function replacedByForkManager() 
    external constant returns (address) {
    }

    function mint(address _to, uint256 _amount) external; 

    function init(address _parentForkManager, address _chainmanager, address _realitio, address _bridgeToL2, bool _hasGovernanceFreeze) external; 

    function realitio() external view returns (IRealitio);

    function bridgeToL2() external view returns (BridgeToL2);

    function requiredBridges() external returns (address[]); 

}
