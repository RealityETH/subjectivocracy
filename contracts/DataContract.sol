pragma solidity ^0.4.13;

contract DataFeed {
	mapping (bytes32 => bytes32) data;
	address public owner;

	function datafeed() {
		owner = msg.sender;
	}

	function set(bytes32 k, bytes32 v) {
		require(owner == msg.sender);
		data[k] = v;
	}

	function get(bytes32 k) public constant returns (bytes32) {
		return data[k];
	}
}
