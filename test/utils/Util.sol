pragma solidity ^0.8.17;

library Util {
    function bytesToAddress(bytes32 b) public pure returns (address) {
        return address(uint160(uint256(b)));
    }
}
