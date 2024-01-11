pragma solidity ^0.8.20;

library Util {
    bytes32 internal constant _IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;
    bytes32 internal constant _ADMIN_SLOT =
        0xb53127684a568b3173ae13b9f8a6016e243e63b6e8ee1178d6a717850b5d6103;

    function bytesToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }
}
