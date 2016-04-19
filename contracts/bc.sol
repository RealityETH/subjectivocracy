contract BorgesCoin {

    struct Branch {
        bytes32 parent_hash;
        bytes32 merkle_root;
        uint timestamp;
        mapping(address => int256) credits;
        mapping(address => int256) debits;
    }

    event LogAddr(address a);
    event LogBranch(bytes32 b);
    event LogBalance(int256 b, string str);

    mapping(bytes32 => Branch) branches;

    // Test framework not handling the constructor well, work around it for now
    function BorgesCoin() {
        _constructor();
    }

    function _constructor() {
        bytes32 genesis_merkel_root = sha3("I leave to several futures (not to all) my garden of forking paths");
        bytes32 null_hash;
        bytes32 genesis_branch_hash = sha3(null_hash, genesis_merkel_root);
        branches[genesis_branch_hash] = Branch(null_hash, genesis_merkel_root, now);
        branches[genesis_branch_hash].credits[msg.sender] = 2100000000000000;
    }

    function sendCoin(address addr, int256 amount, bytes32 to_branch) returns (bool) {
        if (amount < 0) {
            return false;
        }
        if (!isBalanceAtLeast(msg.sender, amount, to_branch)) {
            return false;
        }
        branches[to_branch].debits[msg.sender] += amount;
        branches[to_branch].credits[addr] += amount;
        return true;
    }

    // Crawl up the tree until we get enough, or return false if we never do.
    // You never have less than 0 in any block, so as we go up the tree your balance can only go up.
    // This uses less gas than getBalance, which always has to go all the way to the root.
    function isBalanceAtLeast(address addr, int256 min_balance, bytes32 branch_hash) constant returns (bool) {

        // This needs to be signed because we may count debits before we run into credits higher up the tree
        // ...resulting in a temporarily negative balance
        int256 bal = 0;

        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal += branches[branch_hash].credits[addr] - branches[branch_hash].debits[addr];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;

    }

    function getBalance(address addr, bytes32 branch_hash) constant returns (int256) {

        int256 bal = 0;

        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal = bal + branches[branch_hash].credits[addr] - branches[branch_hash].debits[addr];
            branch_hash = branches[branch_hash].parent_hash;
        }
        return bal;

    }

    function createBranch(bytes32 parent_b_hash, bytes32 merkle_root) returns (bytes32) {
        bytes32 null_hash;
        bytes32 branch_hash = sha3(parent_b_hash, merkle_root);
        // Only the constructor can create the root branch with no parent
        if (branch_hash == null_hash) {
            throw;
        }
        uint parent_ts = branches[parent_b_hash].timestamp;
        if (parent_ts == 0) {
            throw;
        }
        if (now < parent_ts) {
            throw;
        }
        if (now - parent_ts < 86400) {
        //    throw;
        }
        branches[branch_hash] = Branch(parent_b_hash, merkle_root, now);
        return branch_hash;
    }

}
