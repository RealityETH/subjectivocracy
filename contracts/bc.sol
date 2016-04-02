contract BorgesCoin {

    // event LogAddr(address a);

    struct Branch {
        bytes32 parent_hash;
        bytes32 merkle_root;
        mapping(address => uint256) balances;
    }
    event LogBranch(bytes32 b);

    mapping(bytes32 => Branch) branches;

    // Test framework not handling the constructor well, work around it for now
    function BorgesCoin() {
        _constructor();
    }

    function _constructor() {
        bytes32 genesis_merkel_root = sha3("I leave to several futures (not to all) my garden of forking paths");
        bytes32 null_hash;
        bytes32 genesis_branch_hash = sha3(null_hash, genesis_merkel_root);
        branches[genesis_branch_hash] = Branch(null_hash, genesis_merkel_root);
        branches[genesis_branch_hash].balances[msg.sender] = 2100000000000000;
        // LogAddr(msg.sender);
    }

    function sendCoin(address addr, uint256 amount, bytes32 to_branch) returns (bool) {
        if (amount < 0) {
            return false;
        }
        if (!isBalanceAtLeast(msg.sender, amount, to_branch)) {
            return false;
        }
        branches[to_branch].balances[msg.sender] = branches[to_branch].balances[msg.sender] - amount;
        branches[to_branch].balances[addr] = branches[to_branch].balances[addr] + amount;
        return true;
    }

    function sendCoinFromBranches(address addr, uint256 amount, bytes32 to_branch, bytes32[] from_branches) {
        var remaining = amount;
        for(uint256 i=0; i<from_branches.length; i++ ) {
            bytes32 b = from_branches[i];
            if (isBranchDescendedFrom(b, to_branch)) {
                uint256 bal = branches[b].balances[msg.sender];
                if (bal >= remaining) {
                    branches[b].balances[msg.sender] = branches[b].balances[msg.sender] - remaining;
                    remaining = 0;
                } else {
                    branches[b].balances[msg.sender] = 0;
                    remaining = remaining - branches[b].balances[msg.sender];
                }
            }
        }
        if (remaining == 0) {
            branches[to_branch].balances[addr] = branches[to_branch].balances[addr] + amount;
        }
    }

    // Crawl up the tree until we get enough
    // This is cheaper than getBalance, which has to go all the way to the root
    function isBalanceAtLeast(address addr, uint256 min_balance, bytes32 branch_hash) constant returns (bool) {

        uint256 bal = 0;

        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal = bal + branches[branch_hash].balances[addr];
            branch_hash = branches[branch_hash].parent_hash;
            // LogBranch(branch_hash);
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;

    }

    function getBalance(address addr, bytes32 branch_hash) constant returns (uint256) {

        uint256 bal = 0;

        bytes32 null_hash;
        while(branch_hash != null_hash) {
            bal = bal + branches[branch_hash].balances[addr];
            branch_hash = branches[branch_hash].parent_hash;
            // LogBranch(branch_hash);
        }
        return bal;

    }

    function createBranch(bytes32 parent_b_hash, bytes32 merkle_root) returns (bytes32) {
        bytes32 null_hash;
        bytes32 branch_hash = sha3(parent_b_hash, merkle_root);
        // Only the constructor can create the root branch with no parent
        if (branch_hash == null_hash) {
            return null_hash;
        }
        branches[branch_hash] = Branch(parent_b_hash, merkle_root);
        return branch_hash;
    }

    function requestData(bytes32 branch_hash, bytes32 desired_data_hash) {
    }

    function isBranchDescendedFrom(bytes32 branch, bytes32 other_branch) returns (bool) {
        bytes32 parent_hash = branches[branch].parent_hash;
        while (true) {
            Branch parent_branch = branches[parent_hash];
            if (parent_hash == parent_branch.parent_hash) {
                return true;
            }
        }
        return false;
    }

}

