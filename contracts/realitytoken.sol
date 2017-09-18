pragma solidity ^0.4.6;

contract RealityToken {

    struct Branch {
        bytes32 parent_hash; // Hash of the parent branch.
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_cntrct; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp branch was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
        mapping(address => int256) balance_change; // user debits and credits
    }
    mapping(bytes32 => Branch) public branches;

    // Spends, which may cause debits, can only go forwards. 
    // That way when we check if you have enough to spend we only have to go backwards.
    mapping(address => uint256) public last_debit_windows; // index of last user debits to stop you going backwards

    mapping(uint256 => bytes32[]) public window_branches; // index to easily get all branch hashes for a window
    uint256 public genesis_window_timestamp; // 00:00:00 UTC on the day the contract was mined

    function RealityToken() {
        genesis_window_timestamp = now - (now % 86400);
        address NULL_ADDRESS;
        bytes32 NULL_HASH;
        bytes32 genesis_merkle_root = sha3("I leave to several futures (not to all) my garden of forking paths");
        bytes32 genesis_branch_hash = sha3(NULL_HASH, genesis_merkle_root, NULL_ADDRESS);
        branches[genesis_branch_hash] = Branch(NULL_HASH, genesis_merkle_root, NULL_ADDRESS, now, 0);
        branches[genesis_branch_hash].balance_change[msg.sender] = 2100000000000000;
        window_branches[0].push(genesis_branch_hash);
    }

    function createBranch(bytes32 parent_branch_hash, bytes32 merkle_root, address data_cntrct) returns (bytes32) {
        bytes32 NULL_HASH;
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        bytes32 branch_hash = sha3(parent_branch_hash, merkle_root, data_cntrct);
        require(branch_hash != NULL_HASH);

        // Your branch must not yet exist, the parent branch must exist.
        // Check existence by timestamp, all branches have one.
        require(branches[branch_hash].timestamp == 0);
        require(branches[parent_branch_hash].timestamp > 0);

        // We must now be a later 24-hour window than the parent.
        require(branches[parent_branch_hash].window < window);

        branches[branch_hash] = Branch(parent_branch_hash, merkle_root, data_cntrct, now, window);
        window_branches[window].push(branch_hash);
        return branch_hash;
    }

    function getWindowBranches(uint256 window) constant returns (bytes32[]) {
        return window_branches[window];
    }

    function getBalanceAbove(address addr, bytes32 branch_hash) constant returns (uint256) {
        int256 bal = 0;
        bytes32 NULL_HASH;
        while(branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[addr];
            branch_hash = branches[branch_hash].parent_hash;
        }
        return uint256(bal);
    }

    // Crawl up towards the root of the tree until we get enough, or return false if we never do.
    // You never have negative total balance above you, so if you have enough credit at any point then return.
    // This uses less gas than getBalanceAbove, which always has to go all the way to the root.
    function isAmountSpendable(address addr, uint256 _min_balance, bytes32 branch_hash) constant returns (bool) {
        require (_min_balance <= 2100000000000000);
        int256 bal = 0;
        int256 min_balance = int256(_min_balance);
        bytes32 NULL_HASH;
        while(branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[addr];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;
    }

    function sendCoin(address addr, uint256 amount, bytes32 branch_hash) returns (bool) {
        uint256 branch_window = branches[branch_hash].window;

        require(amount <= 2100000000000000);
        require(branches[branch_hash].timestamp > 0); // branch must exist

        if (branch_window < last_debit_windows[msg.sender]) return false; // debits can't go backwards
        if (!isAmountSpendable(msg.sender, amount, branch_hash)) return false; // can only spend what you have

        last_debit_windows[msg.sender] = branch_window;
        branches[branch_hash].balance_change[msg.sender] -= int256(amount);
        branches[branch_hash].balance_change[addr] += int256(amount);
        return true;
    }

}
