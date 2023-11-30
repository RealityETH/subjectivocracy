// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

/** This contract can be inherited form any other contrac that needs to be aware of Forks.
This contract uses the fact that after a fork the chainId changes and thereby detects forks*/

contract InitializeChain {
    uint256 public chainId;

    modifier onlyChainUninitialized() {
        require(chainId != block.chainid, "Not on new fork");
        _;
        chainId = block.chainid;
    }

    modifier onlyChainInitialized() {
        require(chainId == block.chainid, "On new fork");
        _;
    }

    constructor() {
        chainId = block.chainid;
    }
}
