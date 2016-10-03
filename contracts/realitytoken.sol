pragma solidity ^0.4.1;



contract RealityTokenOld {

    struct Branch {
        bytes32 parent_hash; // Hash of the parent branch.
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_contract; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp branch was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
        mapping(address => mapping(address=>int256)) balance_change; // owner->user debits and credits
    }
    mapping(bytes32 => Branch) public branches;
    mapping(address => mapping(address => bool)) public approved_proxies;

    uint256 public totalSupply = 2100000000000000;

    // Spends, which may cause debits, can only go forwards. 
    // That way when we check if you have enough to spend we only have to go backwards.
    mapping(address => mapping(address => uint256)) public last_debit_windows; // index of last user debits to stop you going backwards

    mapping(uint256 => bytes32[]) public window_branches; // index to easily get all branch hashes for a window
    uint256 public genesis_window_timestamp; // 00:00:00 UTC on the day the contract was mined

    function RealityToken() {
        genesis_window_timestamp = now - (now % 86400);
        address NULL_ADDRESS;
        bytes32 NULL_HASH;
        bytes32 genesis_merkle_root = sha3("I leave to several futures (not to all) my garden of forking paths");
        bytes32 genesis_branch_hash = sha3(NULL_HASH, genesis_merkle_root, NULL_ADDRESS);
        branches[genesis_branch_hash] = Branch(NULL_HASH, genesis_merkle_root, NULL_ADDRESS, now, 0);
        branches[genesis_branch_hash].balance_change[msg.sender][msg.sender] = 2100000000000000;
        window_branches[0].push(genesis_branch_hash);
    }

    function createBranch(bytes32 parent_branch_hash, bytes32 merkle_root, address data_contract) returns (bytes32) {
        bytes32 NULL_HASH;
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        bytes32 branch_hash = sha3(parent_branch_hash, merkle_root, data_contract);
        if (branch_hash == NULL_HASH) throw;

        // Your branch must not yet exist, the parent branch must exist.
        // Check existence by timestamp, all branches have one.
        if (branches[branch_hash].timestamp > 0) throw;
        if (branches[parent_branch_hash].timestamp == 0) throw;

        // We must now be a later 24-hour window than the parent.
        if (branches[parent_branch_hash].window >= window) throw;

        branches[branch_hash] = Branch(parent_branch_hash, merkle_root, data_contract, now, window);
        window_branches[window].push(branch_hash);
        return branch_hash;
    }

    function getWindowBranches(uint256 window) constant returns (bytes32[]) {
        return window_branches[window];
    }

    function balanceOfAbove(address manager, address addr, bytes32 branch_hash) constant returns (uint256) {
        int256 bal = 0;
        bytes32 NULL_HASH;
        while(branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[manager][addr];
            branch_hash = branches[branch_hash].parent_hash;
        }
        return uint256(bal);
    }

    // Crawl up towards the root of the tree until we get enough, or return false if we never do.
    // You never have negative total balance above you, so if you have enough credit at any point then return.
    // This uses less gas than getBalanceAbove, which always has to go all the way to the root.
    function isAmountSpendable(address manager, address addr, uint256 _min_balance, bytes32 branch_hash) constant returns (bool) {
        if (_min_balance > 2100000000000000) throw;
        int256 bal = 0;
        int256 min_balance = int256(_min_balance);
        bytes32 NULL_HASH;
        while(branch_hash != NULL_HASH) {
            bal += branches[branch_hash].balance_change[manager][addr];
            branch_hash = branches[branch_hash].parent_hash;
            if (bal >= min_balance) {
                return true;
            }
        }
        return false;
    }

    function transferOnBranch(address addr, uint256 amount, bytes32 branch_hash) returns (bool) {
        return managedTransferFrom(msg.sender, msg.sender, addr, addr, amount, branch_hash);
    }

    function managedTransferFrom(address _from_manager, address _from_owner, address _to_manager, address _to_owner, uint256 amount, bytes32 branch_hash) returns (bool) {

        if ( (_from_manager != msg.sender) && (!approved_proxies[_from_owner][msg.sender]) ) throw;

        uint256 branch_window = branches[branch_hash].window;

        if (amount > 2100000000000000) throw;
        if (branches[branch_hash].timestamp == 0) throw; // branch must exist

        if (branch_window < last_debit_windows[_from_manager][_from_owner]) return false; // debits can't go backwards
        if (!isAmountSpendable(_from_manager, _from_owner, amount, branch_hash)) return false; // can only spend what you have

        last_debit_windows[_from_manager][_from_owner] = branch_window;
        branches[branch_hash].balance_change[_from_manager][_from_owner] -= int256(amount);
        branches[branch_hash].balance_change[_to_manager][_to_owner] += int256(amount);
        return true;
    }

    function approveProxy(address addr) {
        approved_proxies[msg.sender][addr] = true;
    }
    function unapproveProxy(address addr) {
        approved_proxies[msg.sender][addr] = false;
    }

}

/*
You should inherit from StandardToken or, for a token like you would want to
deploy in something like Mist, see HumanStandardToken.sol.
(This implements ONLY the standard functions and NOTHING else.
If you deploy this, you won't have anything useful.)

Implements ERC 20 Token standard: https://github.com/ethereum/EIPs/issues/20
.*/

contract Token {
    /* This is a slight change to the ERC20 base standard.
    function totalSupply() constant returns (uint256 supply);
    is replaced with:
    uint256 public totalSupply;
    This automatically creates a getter function for the totalSupply.
    This is moved to the base contract since public getter functions are not
    currently recognised as an implementation of the matching abstract
    function by the compiler.
    */
    /// total amount of tokens
    uint256 public totalSupply;

    /// @param _owner The address from which the balance will be retrieved
    /// @return The balance
    function balanceOf(address _owner) constant returns (uint256 balance);

    /// @notice send `_value` token to `_to` from `msg.sender`
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transfer(address _to, uint256 _value) returns (bool success);

    /// @notice send `_value` token to `_to` from `_from` on the condition it is approved by `_from`
    /// @param _from The address of the sender
    /// @param _to The address of the recipient
    /// @param _value The amount of token to be transferred
    /// @return Whether the transfer was successful or not
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success);

    /// @notice `msg.sender` approves `_addr` to spend `_value` tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @param _value The amount of wei to be approved for transfer
    /// @return Whether the approval was successful or not
    function approve(address _spender, uint256 _value) returns (bool success);

    /// @param _owner The address of the account owning tokens
    /// @param _spender The address of the account able to transfer the tokens
    /// @return Amount of remaining tokens allowed to spent
    function allowance(address _owner, address _spender) constant returns (uint256 remaining);

    event Transfer(address indexed _from, address indexed _to, uint256 _value);
    event Approval(address indexed _owner, address indexed _spender, uint256 _value);
}

contract StandardToken is Token {

    function transfer(address _to, uint256 _value) returns (bool success) {
        //Default assumes totalSupply can't be over max (2^256 - 1).
        //If your token leaves out totalSupply and can issue more tokens as time goes on, you need to check if it doesn't wrap.
        //Replace the if with this one instead.
        //if (balances[msg.sender] >= _value && balances[_to] + _value > balances[_to]) {}
        if (balances[msg.sender] >= _value && _value > 0) {
            balances[msg.sender] -= _value;
            balances[_to] += _value;
            Transfer(msg.sender, _to, _value);
            return true;
        } else { return false; }
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {}
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function balanceOf(address _owner) constant returns (uint256 balance) {
        return balances[_owner];
    }

    function approve(address _spender, uint256 _value) returns (bool success) {
        allowed[msg.sender][_spender] = _value;
        Approval(msg.sender, _spender, _value);
        return true;
    }

    function allowance(address _owner, address _spender) constant returns (uint256 remaining) {
      return allowed[_owner][_spender];
    }

    mapping (address => uint256) balances;
    mapping (address => mapping (address => uint256)) allowed;

}

contract RealityToken is StandardToken {

    address forked_from_contract;
    uint256 forked_at_window;

    bytes32 owner; // Contract that can publish branches to us
    bytes32 merkle_root; // Merkle root of the data we commit to
    uint256 timestamp; // Timestamp branch was mined

    // Day x of the system's operation, starting at UTC 00:00:00
    uint256 first_window;
    uint256 last_window;

    uint256 genesis_window_timestamp;

    mapping(uint256 => mapping(address=>int256)) balanceChangeOf; // per-window transaction history for forking
    mapping(address=>int256) startingBalanceOf; // The balance when we forked. Not populated until copyBalanceFromParent called.

    mapping(address=>bool) isCopyBalanceFromParentDone; 
    public mapping(window => address[]) child_forks; 

    function RealityToken(uint256 _forked_at_window, address _forked_from_contract, _genesis_window_timestamp) {
        if (_forked_at_window == 0) {
            genesis_window_timestamp = now - (now % 86400);
        } else {
            forked_at_window = _forked_at_window;
            forked_from_contract = _forked_from_contract;
            genesis_window_timestamp = _genesis_window_timestamp;
        }
    }

    function createFork(_window) {
        child_forks[_window].push = new RealityToken(_window, this, genesis_window_timestamp);
    }

    function transfer(address _to, uint256 _value) {
        forkBalanceFromParent(_to);
        if (balanceOf[msg.sender] < _value) throw;
        if (balanceOf[_to] + _value < balanceOf[_to]) throw;
        balanceOf[msg.sender] -= _value;
        balanceOf[_to] += _value;
        balanceChangeOf[window][_to] += int256(_value); 
        balanceChangeOf[window][msg.sender] -= int256(_value); 
        Transfer(msg.sender, _to, _value);
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {}
        uint256 win = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            balanceChangeOf[win][_to] += int256(_value); 
            balanceChangeOf[win][_from] -= int256(_value); 
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function copyBalanceFromParent(address _to) returns (bool) {
        if (isCopyBalanceFromParentDone[_to]) return false;
        address NULL_ADDRESS;
        if (forked_from_contract == NULL_ADDRESS) return false;
        RealityToken parent = RealityToken(forked_from_contract);
        uint256 val = parent.balanceAtWindow(forked_at_window);
        balanceChangeOf[forked_at_window][_to] += int256(_value); 
        balanceOf[_to] += val;
    }

    // Usually you fork near the end not near the beginning
    // So start at the final balance and apply changes backwards
    // NB If we're near the start it may be better to go the other way...
    function balanceAtWindow(_to, _window) constant returns (uint256) {
        uint256 win = last_window; 
        int256 bal = int256(balanceOf[_to]);
        while(win > _window) {
            bal -= balanceChangeOf[win][_to];
            win--; 
        }
        return uint256(win);
    }

    function publishWindow(bytes32 merkle_root, address data_contract) returns (bytes32) {
        bytes32 NULL_HASH;
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        bytes32 merkle_root = sha3(this, window, merkle_root, data_contract);
        if (branch_hash == NULL_HASH) throw;

        // Your branch must not yet exist, the parent branch must exist.
        // Check existence by timestamp, all branches have one.
        if (branches[branch_hash].timestamp > 0) throw;
        if (branches[parent_branch_hash].timestamp == 0) throw;

        // We must now be a later 24-hour window than the parent.
        if (branches[parent_branch_hash].window >= window) throw;

        window_branches[window].push(branch_hash);
        return branch_hash;
    }

    function getWindowBranches(uint256 window) constant returns (bytes32[]) {
        return window_branches[window];
    }

}
