pragma solidity ^0.4.1;

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

// Header for when we need to call ourselves
contract RealityTokenAPI {
    function balanceAtWindow(address _to, uint256 _window) constant returns (uint256) {}
}

contract RealityToken is StandardToken {

    // This will be the timestamp when the system started
    // It should be copied into each new contract whenever we fork
    uint256 public genesis_window_timestamp;

    address public forked_from_contract;
    uint256 public forked_at_window;

    address public owner; // Contract that can publish bundlees to us

    // Day x of the system's operation, starting at UTC 00:00:00
    uint256 public last_window;

    mapping(uint256 => mapping(address=>int256)) public balanceChanges; // per-window transaction history for forking
    mapping(address=>int256) public startingBalanceOf; // The balance when we forked. Not populated until copyBalanceFromParent called.

    mapping(address=>bool) public isCopyBalanceFromParentDone; 
    mapping(uint256 => address[]) public child_forks; 

    struct FactBundle {
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_contract; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp bundle was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
    }
    mapping(uint256 => FactBundle) public fact_bundles;

    function RealityToken(uint256 _forked_at_window, address _forked_from_contract, uint256 _genesis_window_timestamp, address _owner) {
        if (_forked_at_window == 0) {
            owner = msg.sender;
        } else {
            forked_at_window = _forked_at_window;
            forked_from_contract = _forked_from_contract;
            genesis_window_timestamp = _genesis_window_timestamp;
            owner = _owner;
        }
    }

    function transfer(address _to, uint256 _value) returns (bool success) {

        copyBalanceFromParent(_to);

        uint256 window = (now - genesis_window_timestamp) / 86400; // remainder gets rounded down
        if (balances[msg.sender] < _value) throw;
        if (balances[_to] + _value < balances[_to]) throw;
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        balanceChanges[window][_to] += int256(_value); 
        balanceChanges[window][msg.sender] -= int256(_value); 
        Transfer(msg.sender, _to, _value);
        return true;
    }

    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        //same as above. Replace this line with the following if you want to protect against wrapping uints.
        //if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && balances[_to] + _value > balances[_to]) {}
        uint256 win = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
        if (balances[_from] >= _value && allowed[_from][msg.sender] >= _value && _value > 0) {
            balances[_to] += _value;
            balances[_from] -= _value;
            balanceChanges[win][_to] += int256(_value); 
            balanceChanges[win][_from] -= int256(_value); 
            allowed[_from][msg.sender] -= _value;
            Transfer(_from, _to, _value);
            return true;
        } else { return false; }
    }

    function copyBalanceFromParent(address _to) returns (bool) {

        if (isCopyBalanceFromParentDone[_to]) return false;

        address NULL_ADDRESS;
        if (forked_from_contract == NULL_ADDRESS) return false; // no parent

        RealityTokenAPI parent = RealityTokenAPI(forked_from_contract);
        uint256 val = parent.balanceAtWindow(_to, forked_at_window);
        balanceChanges[forked_at_window][_to] += int256(val); 
        balances[_to] += val;
    }

    // Usually you fork near the end not near the beginning
    // So start at the final balance and apply changes backwards
    // TODO If we're near the start it may be better to go the other way...
    function balanceAtWindow(address _to, uint256 _window) constant returns (uint256) {
        uint256 win = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
        int256 bal = int256(balances[_to]);
        while(win > _window) {
            bal -= balanceChanges[win][_to];
            win--; 
        }
        return uint256(win);
    }

    function publishFactBundle(bytes32 merkle_root, address data_contract) returns (bool) {
        uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

        // Only go forwards, max 1 per window
        if (last_window >= window) throw;

        fact_bundles[window] = FactBundle(
            merkle_root,
            data_contract,
            now, 
            window
        );
        return true;
    }

}

contract RealityTokenFactory {

    uint256 genesis_window_timestamp;
    RealityToken genesis_token;

    function createGenesisContract() {
        if (genesis_window_timestamp > 0) throw;
        address NULL_ADDRESS;
        genesis_window_timestamp = now - (now % 86400);
        genesis_token = new RealityToken(0, NULL_ADDRESS, genesis_window_timestamp, msg.sender);
    }

    function createFork(address _parent, uint256 _window) {
        if (genesis_window_timestamp == 0) throw;
        RealityToken rt = new RealityToken(_window, _parent, genesis_window_timestamp, msg.sender);
    }

}
