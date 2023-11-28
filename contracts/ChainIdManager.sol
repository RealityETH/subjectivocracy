// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

import {Owned} from "./mixin/Owned.sol";

contract ChainIdManager is Owned {
    // Counter for the number of Chain IDs
    uint64 public chainIdCounter = 0;
    // contains a list of denied Chain IDs that should not be used as chainIds
    // they are governed by a owner of the contract
    mapping(uint64 => bool) public deniedChainIds;
    // Fee to use up a Chain ID
    uint256 public immutable gasBurnAmount = 1000000;

    constructor(uint64 _chainIdCounter) Owned() {
        chainIdCounter = _chainIdCounter;
    }

    /**
     * @dev Adds a Chain ID to the deny list, this can be done if the chainId is used by another project
     * @param chainId The Chain ID to add
     */
    function denyListChainId(uint64 chainId) public onlyOwner {
        deniedChainIds[chainId] = true;
    }

    /**
     * @dev Adds multiple Chain IDs to the deny list
     * @param chainIds The Chain IDs to add
     */
    function denyListChainIds(uint64[] memory chainIds) public onlyOwner {
        for (uint256 i = 0; i < chainIds.length; i++) {
            denyListChainId(chainIds[i]);
        }
    }

    /**
     * @dev Returns the next usable Chain ID
     * @return chainId The next usable Chain ID
     */
    function getNextUsableChainId() public returns (uint64 chainId) {
        // The burnGas function introduces a cost to use up chainIds.
        // There are uint64(2**63=9.223372e+18) chainIds minus the publicly used chainIds available.
        // Using all of the chainIds would cost 9.223372e+18 * gasBurnAmount = 9.223372e+24 gas = 6.1489147e+17 blocks = 237226647377 years
        burnGas();
        while (deniedChainIds[chainIdCounter]) {
            chainIdCounter++;
        }
        chainId = chainIdCounter;
        chainIdCounter++;
    }

    function burnGas() public view {
        uint256 counter = 0;
        uint256 _lowestLimit = gasleft() - gasBurnAmount;
        while (gasleft() > _lowestLimit) counter++;
    }
}
