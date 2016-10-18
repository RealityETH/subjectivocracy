pragma solidity ^0.4.1;

contract RealityTokenAPI {
    uint256 public genesis_window_timestamp;
    function balanceAtWindow(address _to, uint256 _window) constant returns (uint256) {}
    function balanceOf(address _owner) constant returns (uint256 balance) {}
}

contract RealityToken is StandardToken {

    // This will be the timestamp when the system started
    // It should be copied into each new contract whenever we fork
    uint256 public last_parent_window;
    address public parent_contract;
    uint256 public genesis_window_timestamp;
    address public owner; // Contract that can publish bundlees to us

    // Day x of the system's operation, starting at UTC 00:00:00
    uint256 public last_window;

    mapping(uint256 => mapping(address=>int256)) public balanceChanges; // per-window transaction history for forking
    mapping(address=>bool) public isCopyBalanceFromParentDone; 

    struct FactBundle {
        bytes32 merkle_root; // Merkle root of the data we commit to
        address data_contract; // Optional address of a contract containing this data
        uint256 timestamp; // Timestamp bundle was mined
        uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
    }
    mapping(uint256 => FactBundle) public fact_bundles;

    function RealityToken(uint256 _last_parent_window, address _parent_contract, address _owner) {
        //initialize(_last_parent_window, _parent_contract, _genesis_window_timestamp, _owner);
    }

    // TODO remove this, just use the constructor
    function initialize(uint256 _last_parent_window, address _parent_contract, address _owner) {
        address NULL_ADDRESS;

        if (_parent_contract == NULL_ADDRESS) { // genesis contract
            genesis_window_timestamp = (now / 86400) * 86400; // NB remainder gets rounded down
            if (_last_parent_window > 0) throw;
            balanceChanges[0][msg.sender] = 2100000000000000;
            balances[msg.sender] = 2100000000000000;
        } else {
            RealityTokenAPI parent = RealityTokenAPI(_parent_contract);
            genesis_window_timestamp = parent.genesis_window_timestamp();
            uint256 win = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
            if (win <= _last_parent_window) throw; // you must be later than the parent
        }

        last_parent_window = _last_parent_window;
        parent_contract = _parent_contract;
        owner = _owner;
    }

    function transfer(address _to, uint256 _value) returns (bool success) {

        copyBalanceFromParent(msg.sender);
        copyBalanceFromParent(_to);
        /*
        if (copyBalanceFromParent(_to)) {
            LogMe("copied balance", _to, balances[msg.sender]);
        } else {
            LogMe("copy  balance returned false", this, balances[msg.sender]);

        }
        */

        uint256 window = (now - genesis_window_timestamp) / 86400; // remainder gets rounded down
        if (balances[msg.sender] < _value) throw;
        if (balances[_to] + _value < balances[_to]) throw;
        balances[msg.sender] -= _value;
        balances[_to] += _value;
        balanceChanges[window][_to] += int256(_value); 
        balanceChanges[window][msg.sender] -= int256(_value); 
        //LogMe("after send sender has ", msg.sender, balances[msg.sender]);
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
        if (isCopyBalanceFromParentDone[_to]) { 
            return false;
        }

        address NULL_ADDRESS;
        if (parent_contract == NULL_ADDRESS) {
//LogMe("no parent_contract", this, 0);
            return false; // no parent
        }
//LogMe("going ahead with copy", this, 0);

        RealityTokenAPI parent = RealityTokenAPI(parent_contract);
        uint256 val = parent.balanceAtWindow(_to, last_parent_window);
        isCopyBalanceFromParentDone[_to] = true;
        balanceChanges[last_parent_window][_to] += int256(val); 
        balances[_to] += val;
        return true;
    }

    // Usually you fork near the end not near the beginning
    // So start at the final balance and apply changes backwards
    // TODO If we're near the start it may be better to go the other way...
    function balanceAtWindow(address _owner, uint256 _window) constant returns (uint256) {
        uint256 win = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
        int256 bal = int256(balances[_owner]);

        // If the window is the last, and we have the user's balance, we can just return that
        if (_window >= win) {
            if (isCopyBalanceFromParentDone[_owner] || (parent_contract == NULL_ADDRESS)) { 
                return balances[_owner];
            }
        }


        while(win > _window) {
            bal -= balanceChanges[win][_owner];
            win--; 
        }
        return uint256(bal);
    }

    function getWindowForTimestamp(uint256 ts) constant returns (uint256) {
        return (ts - genesis_window_timestamp) / 86400; // NB remainder gets rounded down
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

    function balanceOf(address _owner) constant returns (uint256 balance) {
        address NULL_ADDRESS;
        if (isCopyBalanceFromParentDone[_owner] || (parent_contract == NULL_ADDRESS)) { 
            return balances[_owner];
        } else {
            RealityTokenAPI parent = RealityTokenAPI(parent_contract);
            uint256 val = parent.balanceAtWindow(_owner, last_parent_window);
            return val; 
        }
    }

    event LogMe(string str, address addr, uint256 num);

}
