pragma solidity ^0.8.17;

contract ForkAwareStructureOnL2 {
    uint256 public chainId;

    modifier onlyFirstTxAfterFork() {
        require(chainId != block.chainid, "Not on new fork");
        _;
        chainId = block.chainid;
    }

    modifier everyButFirstTxAfterFork() {
        require(chainId == block.chainid, "On new fork");
        _;
    }

    constructor() {
        chainId = block.chainid;
    }
}
