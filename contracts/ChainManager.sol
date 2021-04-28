pragma solidity ^0.4.25;

// An L2 system generally has some contract like this that lives on the L1 and commits to data on L2.
// It should be able to tell us what contract to use to send transactions to its L2.
contract ChainManager {

    address bridgeFromL1ToL2;

    bytes32 ledgerHash;

    // Imagine something like this with an owner committing blocks for the OVM etc, something about the L2 ledger is committed to L1
    function addBlock(bytes32 _ledgerHash) external {
        // Whatever we check to make sure this is legit goes here
        ledgerHash = _ledgerHash;
    }

    /*
    function cloneForFork() 
    public returns (ChainManager) {
        // Copy anything that needs copying, we may need the ledgerHash etc depending on the details of the L2 system
        ChainManager chainmanager = new ChainManager(bridgeFromL1ToL2.cloneForFork());
        return chainmanager;
    }
    */

}
