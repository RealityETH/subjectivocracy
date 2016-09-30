contract BranchMarket {

    address token_contract;

    struct Offer(
        address seller;
        bytes32 branch;
        uint256 window;
        uint256 price;
        uint256 amount;
        uint256 offered_ts;
        uint256 taken_ts;
        uint256 nonce;
    );

    mapping(bytes32 => Offer) public offers;
    mapping(uint256 => mapping(uint256 => bytes32)) public best_price_for_branch_window;

    ? how to tell minimum offer ?
    ? how to tell minimum period ?

    function BranchMarket(address _token_contract) {
        token_contract = _token_contract;
    }

    // Make a deterministic offer ID so the offerer can create an offer then know what they created
    // However, hash it with the offerer address to prevent people generating collisions
    function issueOfferID(address offerer, uint256 nonce) constant returns (bytes32) {
        return sha3(offerer, nonce);
    }

    function makeOffer(bytes32 branch_hash, uint256 price, uint256 amount, uint256 nonce) {
        if (amount > 2100000000000000) throw;
        if (!token_contract.managedTransferFrom(msg.sender, msg.sender, this, msg.sender, amount)) throw;

        // Use a user-defined nonce to allow the user to assign an ID deterministically
        bytes32 offer_id = issueOfferID(msg.sender, nonce);

        if (offers[offer_id].offered_ts > 0) throw; // already exists
        int256 window = token_contract.windowForBranchIfExists(branch_hash);
        if (window == -1) throw; // non-existent branch

        offers[offer_id] = Offer(
            msg.sender,
            branch,
            uint256(window),
            amount, 
            price,
            now,
            0,
            nonce 
        ); 

        // buy_offers[msg.sender][branch_hash][price] += amount; 
    }

    function takeOffer(bytes32 offer_id) {

    }

    function claimBest(offer_id) {

    }

}
