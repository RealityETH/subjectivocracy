pragma ^0.8.17;

contract ForkAwareStructureOnL2 {
    uint256 public  chainId;

    modifier onlyFirstTxAfterFork() {
        require(chainId != block.chainid, "ForkAwareStructureOnL2: Not on fork");
        _;
        chainId = block.chainid;
    }

    modifier everyButFirstTxAfterFork() {
        require(chainId == block.chainid, "ForkAwareStructureOnL2: On fork");
        _;
    }

    constructor(uint256 _chainId) {
        chainId = _chainId;
    }
}