contract RealityToken {

    struct Branch {
        bytes32 parent_hash;
        bytes32 merkle_root;
        uint256 timestamp;
        uint256 height;
        mapping(address => int256) balance_change;
    }

    mapping(bytes32 => Branch) public branches;
    mapping(address => uint256) public user_heights;

    function RealityToken() {
        bytes32 null_hash;
        bytes32 genesis_merkel_root = sha3("I leave to several futures (not to all) my garden of forking paths");
        bytes32 genesis_branch_hash = sha3(null_hash, genesis_merkel_root);
        branches[genesis_branch_hash] = Branch(null_hash, genesis_merkel_root, now, 0);
        branches[genesis_branch_hash].balance_change[msg.sender] = 2100000000000000;
    }

    function sendCoin(address addr, uint256 amount, bytes32 to_branch) returns (bool) {
        if (amount > 2100000000000000) {
            throw;
        }
        // You can only go forwards. 
        // That way when we check if you have enough to spend we only have to go backwards.
        uint256 branch_height = branches[to_branch].height;
        if (branch_height < user_heights[msg.sender]) {
            return false;
        }
        if (!isBalanceAtLeast(msg.sender, amount, to_branch)) {
            return false;
        }
        user_heights[msg.sender] = branches[to_branch].height; 
        branches[to_branch].balance_change[msg.sender] -= int256(amount);
        branches[to_branch].balance_change[addr] += int256(amount);
        return true;
    }

    // Crawl up towards the root of the tree until we get enough, or return false if we never do.
    // You never have negative balance above you, so if you have enough credit at any point then return.
    // This uses less gas than getBalance, which always has to go all the way to the root.
    function isBalanceAtLeast(address addr, uint256 _min_balance, bytes32 branch_hash) constant returns (bool) {
        if (_min_balance > 2100000000000000) {
            throw;
        }
        int256 bal = 0;
        int256 min_balance = int256(_min_balance);
        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal += branches[branch_hash].balance_change[addr];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;
    }

    function getBalance(address addr, bytes32 branch_hash) constant returns (uint256) {
        int256 bal = 0;
        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal += branches[branch_hash].balance_change[addr];
            branch_hash = branches[branch_hash].parent_hash;
        }
        return uint256(bal);
    }

    function createBranch(bytes32 parent_b_hash, bytes32 merkle_root) returns (bytes32) {
        bytes32 null_hash;
        bytes32 branch_hash = sha3(parent_b_hash, merkle_root);
        // Probably impossible to make sha3 come out all zeroes but check to be safe
        if (branch_hash == null_hash) {
            throw;
        }
        // You can only create a branch once
        if (branches[branch_hash].timestamp > 0) {
            throw;
        }
        uint256 parent_ts = branches[parent_b_hash].timestamp;
        // The parent branch must exist and have a timestamp
        if (parent_ts == 0) {
            throw;
        }
        if (now < parent_ts) {
            throw;
        }
        if (now - parent_ts < 86400) {
        //    throw;
        }
        branches[branch_hash] = Branch(parent_b_hash, merkle_root, now, branches[parent_b_hash].height + 1);
        return branch_hash;
    }
}
