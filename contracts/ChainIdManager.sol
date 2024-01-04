// SPDX-License-Identifier: GPL-3.0-only
pragma solidity ^0.8.20;

// The ChainIdManager contract provides a list of new usable chainIds via the getNextUsableChainId function.
// If a project uses one chainId, it can be added to the deny list and then no other project will use it.
// The contract does not come with an owner, but anyone can add chainIds to the deny list.
// It costs just gasBurnAmount to deny list a chainId.
// The burnGas function introduces this cost to use up chainIds.
// There are uint64(2**63=9.223372e+18) chainIds minus the publicly used chainIds available.
// Using all of the chainIds would cost 9.223372e+18 * gasBurnAmount = 9.223372e+24 gas = 6.1489147e+17 blocks = 237226647377 years

contract ChainIdManager {
    // Counter for the number of Chain IDs
    uint64 public chainIdCounter = 0;
    // contains a list of denied Chain IDs that should not be used as chainIds
    // they are anyone who is willing to pay the gas to use them.
    mapping(uint64 => bool) public deniedChainIds;
    // Fee to use up a chain ID
    uint256 public immutable gasBurnAmount = 1000000;

    constructor(uint64 _chainIdCounter) {
        chainIdCounter = _chainIdCounter;
    }

    /**
     * @dev Adds a Chain ID to the deny list, this can be done if the chainId is used by another project
     * @param chainId The Chain ID to add
     */
    function denyListChainId(uint64 chainId) public {
        burnGas();
        deniedChainIds[chainId] = true;
    }

    /**
     * @dev Adds multiple Chain IDs to the deny list
     * @param chainIds The Chain IDs to add
     */
    function denyListChainIds(uint64[] memory chainIds) public {
        for (uint256 i = 0; i < chainIds.length; i++) {
            denyListChainId(chainIds[i]);
        }
    }

    /**
     * @dev Returns the next usable Chain ID
     * @return chainId The next usable Chain ID
     */
    function getNextUsableChainId() public returns (uint64 chainId) {
        burnGas();
        while (deniedChainIds[chainIdCounter]) {
            chainIdCounter++;
        }
        chainId = chainIdCounter;
        chainIdCounter++;
    }

    /**
     * @dev Burns gasBurnAmount gas to incure a cost for everyone calling this function
     */
    function burnGas() public view {
        uint256 counter = 0;
        uint256 _lowestLimit = gasleft() - gasBurnAmount;
        while (gasleft() > _lowestLimit) counter++;
    }
}
