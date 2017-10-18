contract DataFeed {
	mapping ( bytes32 => int256 ) data;
	address owner;

	function datafeed() {
		owner = msg.sender;
	}

	function set(bytes32 k, bytes32 v) {
		require(owner == msg.sender);
		data[k] = v;
	}

	function get(bytes32 k) returns (bytes32 v) {
		v = data[k];
	}
}
