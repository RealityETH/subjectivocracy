contract RealityTokenAPI {
    function managedTransferFrom(address _from_manager, address _from_owner, address _to_manager, address _to_owner, uint256 amount, bytes32 branch_hash) returns (bool) {}
}

/*
This represents a RealityToken which has an opinion about which branch is correct.
It exposes syntax that looks like a normal token.
*/

contract DictatorshipPortalToken { 
// The owner can update the branch.
// Others will have different forms of governance

    bytes32 public branch;
    RealityTokenAPI public realitytoken;
    address public owner;

    function DictatorshipPortalToken(address _realitytoken) {
        owner = msg.sender;
    }

    function setRealityToken(address _addr) {
        if (owner != msg.sender) throw;
        realitytoken = RealityTokenAPI(_addr);
    }

    function setBranch(bytes32 _branch) {
        if (owner != msg.sender) throw;
        branch = _branch; 
    }

    // A vanilla transfer, on the current branch.
    // Owner and manager are the same person for both sender and receiver.
    function transfer(address _to, uint256 _value) returns (bool success) {
        return realitytoken.managedTransferFrom(msg.sender, msg.sender, _to, _to, _value, branch);
    }

    // NB This requires that ufnds have been "approved", where approval actually locks the funds.
    // TODO: Maybe this should be called "transferLockedFundsFrom()"
    function transferFrom(address _from, address _to, uint256 _value) returns (bool success) {
        // msg.sender is the manager, they specify the owner
        // this will fail if they're not permitted
        return realitytoken.managedTransferFrom(msg.sender, _from, _to, _to, _value, branch);
    }

    // NB This does something subtly different to the normal approve: 
    // This actually moves _value to the control of _spender.
    // The owner is no longer able to spend it.
    // TODO: Maybe this should be called "lock()".
    function approve(address _spender, uint256 _value) returns (bool success) {
        return realitytoken.managedTransferFrom(msg.sender, msg.sender, _spender, msg.sender, _value, branch);
    }

}
