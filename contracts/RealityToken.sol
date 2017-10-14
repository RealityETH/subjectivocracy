pragma solidity ^0.4.6;

contract RealityToken {

    event Approval(address indexed _owner, address indexed _spender, uint _value, bytes32 branch);
    event Transfer(address indexed _from, address indexed _to, bytes32 _from_sub, bytes32 _to_sub, uint _value, bytes32 branch);
    event BranchCreated(bytes32 hash, address data_cntrct);

    bytes32 constant NULL_HASH = "";
    address constant NULL_ADDRESS = 0x0;

    struct Branch {
        bytes32 parent_hash; // Hash of the parent branch.
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_cntrct; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp branch was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
        mapping(bytes32 => int256) balance_change; // user-account debits and credits
    }
    mapping(bytes32 => Branch) public branches;

    // Spends, which may cause debits, can only go forwards.
    // That way when we check if you have enough to spend we only have to go backwards.
    mapping(bytes32 => uint256) public last_debit_windows; // index of last user debits to stop you going backwards

    mapping(uint256 => bytes32[]) public window_branches; // index to easily get all branch hashes for a window
    uint256 public genesis_window_timestamp; // 00:00:00 UTC on the day the contract was mined

    mapping(address => mapping(address => mapping(bytes32=> uint256))) allowed;


    function RealityToken()
    public {
        genesis_window_timestamp = now - (now % 86400);
        bytes32 genesis_merkle_root = keccak256("I leave to several futures (not to all) my garden of forking paths");
        bytes32 genesis_branch_hash = keccak256(NULL_HASH, genesis_merkle_root, NULL_ADDRESS);
        branches[genesis_branch_hash] = Branch(NULL_HASH, genesis_merkle_root, NULL_ADDRESS, now, 0);
        branches[genesis_branch_hash].balance_change[keccak256(msg.sender, NULL_HASH)] = 2100000000000000;
        window_branches[0].push(genesis_branch_hash);
    }

    function createBranch(bytes32 parent_branch_hash, bytes32 merkle_root, address data_cntrct)
    public returns (bytes32) {
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        bytes32 branch_hash = keccak256(parent_branch_hash, merkle_root, data_cntrct);
        require(branch_hash != NULL_HASH);

        // Your branch must not yet exist, the parent branch must exist.
        // Check existence by timestamp, all branches have one.
        require(branches[branch_hash].timestamp == 0);
        require(branches[parent_branch_hash].timestamp > 0);

        // We must now be a later 24-hour window than the parent.
        require(branches[parent_branch_hash].window < window);

        branches[branch_hash] = Branch(parent_branch_hash, merkle_root, data_cntrct, now, window);
        window_branches[window].push(branch_hash);
        BranchCreated(branch_hash,data_cntrct);
        return branch_hash;
    }

    function getWindowBranches(uint256 window)
    public constant returns (bytes32[]) {
        return window_branches[window];
    }

    function approve(address _spender, uint256 _amount, bytes32 _branch)
    public returns (bool success) {
        allowed[msg.sender][_spender][_branch] = _amount;
        Approval(msg.sender, _spender, _amount, _branch);
        return true;
    }

    function allowance(address _owner, address _spender, bytes32 branch)
    constant public returns (uint remaining) {
        return allowed[_owner][_spender][branch];
    }

    function balanceOf(address addr, bytes32 branch)
    public constant returns (uint256) {
        return balanceOfSub(addr, branch, NULL_HASH);
    }

    function balanceOfSub(address addr, bytes32 branch, bytes32 acct)
    public constant returns (uint256) {
        int256 bal = 0;
        while(branch != NULL_HASH) {
            bal += branches[branch].balance_change[keccak256(addr, acct)];
            branch = branches[branch].parent_hash;
        }
        return uint256(bal);
    }

    // Crawl up towards the root of the tree until we get enough, or return false if we never do.
    // You never have negative total balance above you, so if you have enough credit at any point then return.
    // This uses less gas than balanceOfAbove, which always has to go all the way to the root.
    function _isAmountSpendable(bytes32 acct, uint256 _min_balance, bytes32 branch_hash)
    internal constant returns (bool) {
        require (_min_balance <= 2100000000000000);
        int256 bal = 0;
        int256 min_balance = int256(_min_balance);
        while(branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[acct];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;
    }

    function isAmountSpendable(address addr, uint256 _min_balance, bytes32 branch_hash)
    public constant returns (bool) {
        return _isAmountSpendable(keccak256(addr, NULL_HASH), _min_balance, branch_hash);
    }

    function isAmountSpendableSub(address addr, uint256 _min_balance, bytes32 branch_hash, bytes32 acct)
    public constant returns (bool) {
        return _isAmountSpendable(keccak256(addr, acct), _min_balance, branch_hash);
    }

    function transferFromSub(address from, address addr, uint256 amount, bytes32 branch, bytes32 from_acct, bytes32 to_acct)
    public returns (bool) {

        require(allowed[from][msg.sender][branch] >= amount);

        uint256 branch_window = branches[branch].window;

        require(amount <= 2100000000000000);
        require(branches[branch].timestamp > 0); // branch must exist

        if (branch_window < last_debit_windows[keccak256(from, NULL_HASH)]) return false; // debits can't go backwards
        if (!_isAmountSpendable(keccak256(from, from_acct), amount, branch)) return false; // can only spend what you have

        last_debit_windows[keccak256(from, NULL_HASH)] = branch_window;
        branches[branch].balance_change[keccak256(from, from_acct)] -= int256(amount);
        branches[branch].balance_change[keccak256(addr, to_acct)] += int256(amount);

        uint256 allowed_before = allowed[from][msg.sender][branch];
        uint256 allowed_after = allowed_before - amount;
        assert(allowed_before > allowed_after);

        Transfer(from, addr, NULL_HASH, NULL_HASH, amount, branch);

        return true;
    }

    function transferFrom(address from, address addr, uint256 amount, bytes32 branch)
    public returns (bool) {
        return transferFromSub(from, addr, amount, branch, NULL_HASH, NULL_HASH);
    }

    function transferSub(address addr, uint256 amount, bytes32 branch, bytes32 from_acct, bytes32 to_acct)
    public returns (bool) {
        uint256 branch_window = branches[branch].window;

        require(amount <= 2100000000000000);
        require(branches[branch].timestamp > 0); // branch must exist

        if (branch_window < last_debit_windows[keccak256(msg.sender, from_acct)]) return false; // debits can't go backwards
        if (!_isAmountSpendable(keccak256(msg.sender, from_acct), amount, branch)) return false; // can only spend what you have

        last_debit_windows[keccak256(msg.sender, from_acct)] = branch_window;
        branches[branch].balance_change[keccak256(msg.sender, from_acct)] -= int256(amount);
        branches[branch].balance_change[keccak256(addr, to_acct)] += int256(amount);

        Transfer(msg.sender, addr, from_acct, to_acct, amount, branch);

        return true;
    }

    function transfer(address addr, uint256 amount, bytes32 branch, bytes32 from_acct)
    public returns (bool) {
        return transferSub(addr, amount, branch, from_acct, NULL_HASH);
    }

    function transfer(address addr, uint256 amount, bytes32 branch)
    public returns (bool) {
        return transferSub(addr, amount, branch, NULL_HASH, NULL_HASH);
    }

    function getDataContract(bytes32 _branch)
    public constant returns (address) {
        return branches[_branch].data_cntrct;
    }

    function getWindowOfBranch(bytes32 _branchHash)
    public constant returns (uint id) {
        return branches[_branchHash].window;
    }

    function isBranchInBetweenBranches(bytes32 investigationHash,bytes32 closerToRootHash, bytes32 fartherToRootHash)
    public constant returns (bool) {
        bytes32 iterationHash = closerToRootHash;
        while (iterationHash != fartherToRootHash) {
            if (investigationHash == iterationHash) {
                return true;
            } else{
                iterationHash = branches[iterationHash].parent_hash;
            }
        }
        return false;
    }

}
