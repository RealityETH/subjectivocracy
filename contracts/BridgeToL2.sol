pragma solidity 0.4.25;

import './IAMB.sol';

contract BridgeToL2 is IAMB {

    address parent;

    // Arbitrary special address that will identify the forkmanager
    // This makes it look to the WhitelistArbitrator like the ForkManager never changed
    address constant FORK_MANAGER_SPECIAL_ADDRESS = 0x00000000000000000000000000000000f0f0F0F0;

    function setParent(address _fm) 
    public {
        require(parent == address(0), "Parent already initialized");
        parent = _fm;
    }

}
