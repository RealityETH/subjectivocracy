pragma solidity ^0.4.25;

import './IERC20.sol';
import './IRealitio.sol';

contract IForkManager is IERC20 {

    function replacedByForkManager() 
    external constant returns (address) {
    }

    function mint(address _to, uint256 _amount) external; 

    function init(address _parentForkManager, address _chainmanager, address _realitio, address _bridgeToL2) external; 

    function realitio() external view returns (IRealitio);

}
