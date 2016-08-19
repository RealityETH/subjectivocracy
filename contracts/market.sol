contract Market {

    address token_contract;
    mapping(address => mapping(branch_hash => balance)) balances_held;
    mapping(address => mapping(branch_hash => balance)) balances_offered;

    function Market(address _token_contract) {
        token_contract = _token_contract;
    }

}
