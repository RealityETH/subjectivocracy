// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import './IERC20.sol';
import './ERC20.sol';

import './ForkableRealityETH_ERC20.sol';
import './Arbitrator.sol';
import './WhitelistArbitrator.sol';
import './Auction_ERC20.sol';
// import './BridgeToL2.sol';
import './ZKBridgeToL2.sol';


/*
    enum OpTree {
        Full,
        Rollup
    }

    enum QueueType {
        Deque,
        HeapBuffer,
        Heap
    }
*/



contract ForkManager is Arbitrator, IERC20, ERC20 {

    // The way we access L2
    ZKBridgeToL2 public bridgeToL2;

    // If we fork, our parent will be able to tell us to mint funds
    ForkManager public parentForkManager;

    // We use a special non-standard Reality.eth instance for governance and arbitration whitelist management
    ForkableRealityETH_ERC20 public realityETH;

    // When we try to add or remove an arbitrator or upgrade the bridge, use this timeout for the reality.eth question
    uint32 constant public REALITY_ETH_TIMEOUT = 604800; // 1 week

    // The standard reality.eth delimiter for questions with multiple arguments
    string constant public QUESTION_DELIM = "\u241f";
   
    // Each each type of proposition we handle has its own template.
    // These are created by ForkableRealityETH_ERC20 in its constructor
    uint256 constant public TEMPLATE_ID_ADD_ARBITRATOR = 2147483648;
    uint256 constant public TEMPLATE_ID_REMOVE_ARBITRATOR = 2147483649;
    uint256 constant public TEMPLATE_ID_BRIDGE_UPGRADE = 2147483650;

    enum PropositionType {
        NONE,
        ADD_ARBITRATOR,
        REMOVE_ARBITRATOR,
        UPGRADE_BRIDGE
    }

    // We act as the arbitrator for the ForkableRealityETH_ERC20 instance. We arbitrate by forking.
    // Our fee to arbitrate (ie fork) will be 5% of total supply.
    // Usually you'd do this as part of a reality.eth arbitration request which will fund you, although you don't have to.
    uint256 constant public PERCENT_TO_FORK = 5;

    // 1% of total supply can freeze the bridges while we ask a governance question
    uint256 constant public PERCENT_TO_FREEZE = 1;

    // In a fork, give people 1 week to pick a side. After that, we will declare one side the "winner".
    uint256 constant public FORK_TIME_SECS = 604800; // 1 week

    // If we fork over one question, but bridges are already frozen over another, we reset any outstanding questions on child forks and you have to ask them again.
    // However we keep the bridges frozen to give you time to recreate the question over which you froze the bridges.
    // After this time, if nobody recreated them, they will be automatically unfrozen
    uint256 constant public POST_FORK_FREEZE_TIMEOUT = 604800;

    // A list of questions that have been used to freeze governance
    mapping(bytes32 => bool) governance_freeze_question_ids;
    uint256 numGovernanceFreezes;

    // The reality.eth question over which we forked. This should be migrated so you can claim bonds on each fork.
    bytes32 fork_question_id;
    // The user who paid for a fork. They should be credited as the right answerer on the fork that went the way they said it should.
    address forkRequestUser;

    // The timestamp when were born in a fork. 0 for the genesis ForkManager.
    uint256 forkedFromParentTs = 0;

    // Governance questions will be cleared when we fork, if you still care about them you can ask them again.
    // However, if we forked over arbitration but had some unresolved governance questions, we stay frozen initially to give people time to recreate them
    uint256 initialGovernanceFreezeTimeout;

    // If we fork we will produce two children
    ForkManager public childForkManager1;
    ForkManager public childForkManager2;

    Auction_ERC20 public auction;

    // Once the fork is resolved you can set the winner to one of the childForkManagers
    ForkManager public replacedByForkManager;

    // The total supply of the parent when our fork was born.
    // We use this as a freeze threshold when it's too early to use our own supply because people are still migrating funds.
    uint256 public parentSupply;

    // The total supply we had when we forked
    // Kept so we can tell our children what to set as their parentSupply
    uint256 supplyAtFork;

    // The deadline for moving funds, when we will decide which fork won.
    uint256 forkTS = 0;

    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition{
        PropositionType proposition_type;
        address whitelist_arbitrator;
        address arbitrator;
        address bridge;
    }
    mapping(bytes32 => ArbitratorProposition) propositions;

    // Libraries used when creating the child contracts in a fork.
    // In theory we could query the current proxies for this information rather than tracking it here.
    // In practice it seems hairy (either use ContractProbe which looks complex or modify the generic proxy contract to be able to return its library address)
    address payable libForkManager;
    address libForkableRealityETH;
    address libBridgeToL2;

    function init(address payable _parentForkManager, address _realityETH, address _bridgeToL2, bool _has_governance_freeze, uint256 _parentSupply, address payable _libForkManager, address _libForkableRealityETH, address _libBridgeToL2, address _initialRecipient, uint256 _initialSupply) 
    external {

        require(address(libForkManager) == address(0), "init can only be run once");

        libForkManager = _libForkManager;
        libForkableRealityETH = _libForkableRealityETH;
        libBridgeToL2 = _libBridgeToL2;

        require(address(_realityETH) != address(0), "RealityETH address must be supplied");
        require(address(_bridgeToL2) != address(0), "Bridge address must be supplied");

        parentForkManager = ForkManager(_parentForkManager); // 0x0 for genesis

        realityETH = ForkableRealityETH_ERC20(_realityETH);
        bridgeToL2 = ZKBridgeToL2(_bridgeToL2);

        if (_has_governance_freeze) {
            initialGovernanceFreezeTimeout = block.timestamp + POST_FORK_FREEZE_TIMEOUT;
        }
        parentSupply = _parentSupply;
        
        // Genesis
        if (_parentForkManager == address(0x0)) {
            totalSupply = _initialSupply;
            balanceOf[_initialRecipient] = _initialSupply;
        } else {
            forkedFromParentTs = block.timestamp;
        }

    }

    // Import the proposition we forked over from the parent ForkManager to ourselves.
    // (This could be done in init but it already has a lot of parameters.)
    function importProposition(bytes32 question_id, PropositionType proposition_type, address whitelist_arbitrator, address arbitrator, address new_bridge) 
    external {
        require(address(libForkManager) == address(0), "Must be run before init");
        propositions[question_id] = ArbitratorProposition(proposition_type, whitelist_arbitrator, arbitrator, new_bridge);
    }

    // Usually we use totalSupply to tell us how many tokens you should need to freeze bridges.
    // But when we just forked, the ultimate totalSupply won't be not known until migration is complete.
    // During that period, substitute an approximation for how many tokens the parent had.
    function effectiveTotalSupply()
    internal view returns (uint256) {
        if (forkedFromParentTs == 0 || (block.timestamp - forkedFromParentTs > FORK_TIME_SECS)) {
            return totalSupply;
        } else {
            uint256 halfParent = parentSupply / 2;
            return (halfParent > totalSupply) ? halfParent : totalSupply;
        }
    }

    // Our tokens are minted either on initial genesis deployment, on choice of a fork, or on import of the proposition over which we forked.
    function mint(address _to, uint256 _amount) 
    external {
        require(msg.sender == address(parentForkManager), "Only our parent can mint tokens");
        totalSupply = totalSupply + _amount;
        balanceOf[_to] = balanceOf[_to] + _amount;
        emit Transfer(address(0), _to, _amount);
    }

    // Function to clone ourselves.
    // This in turn clones the realityETH instance and the bridge.
    // TODO: It should also clone the L1 rollup contract.
    // An arbitrator fork will create this for both forks.
    // A governance fork will use the specified contract for one of the options.
    // It can have its own setup logic if you want to change the RealityETH or bridge code.
    function deployFork(bool yes_or_no, bytes32 last_history_hash, bytes32 last_answer, address last_answerer, uint256 last_bond) 
    external {

        require(block.timestamp >= forkTS, "Too soon to fork");

        bytes32 result;
        if (yes_or_no) {
            require(address(childForkManager1) == address(0), "Already migrated");
            result = bytes32(uint256(1));
        } else {
            require(address(childForkManager2) == address(0), "Already migrated");
            result = bytes32(uint256(0));
        }

        // Verify that last_answerer and last_answerer match the current history hash 
        bytes32 history_hash = realityETH.getHistoryHash(fork_question_id);
        require(history_hash == keccak256(abi.encodePacked(last_history_hash, last_answer, last_bond, last_answerer, false)), "Wrong parameters supplied for last answer");

        require(fork_question_id != bytes32(uint256(0)), "Fork not initiated");

        uint256 migrate_funds = realityETH.getCumulativeBonds(fork_question_id);

        ForkManager newFm = ForkManager(payable(_deployProxy(libForkManager)));

        address bridgeLibForThisDeployment;


        // If this is a bridge upgrade proposition, we use the specified bridge for the yes fork.
        // Otherwise we just clone the one used by the current ForkManager.
        bool upgrade_bridge = (yes_or_no && (propositions[fork_question_id].proposition_type == PropositionType.UPGRADE_BRIDGE));
        if (upgrade_bridge) {
            bridgeLibForThisDeployment = propositions[fork_question_id].bridge;
        } else {
            bridgeLibForThisDeployment = libBridgeToL2;
        }

        // The new bridge should let us call these without error, even if it doesn't need them.
        ZKBridgeToL2 newBridgeToL2 = ZKBridgeToL2(_deployProxy(bridgeLibForThisDeployment));
        newBridgeToL2.setParent(address(this));
        newBridgeToL2.init();

        /* VARIATION:
        // We might not want to hack the BridgeToL2 to know about its parent forkmanager
        // In that case, have a single proxy shared by all forkmanagers to manage the mapping newBridgeToL2 => this
        // ...then proxy all calls to the bridge through that.
        */

        ForkableRealityETH_ERC20 newRealityETH = ForkableRealityETH_ERC20(_deployProxy(libForkableRealityETH));
        newRealityETH.init(IERC20(newFm), address(realityETH), fork_question_id);

        address payee = last_answer == result ? last_answerer : forkRequestUser;
        newRealityETH.submitAnswerByArbitrator(fork_question_id, result, payee);

        newFm.importProposition(fork_question_id, propositions[fork_question_id].proposition_type, propositions[fork_question_id].whitelist_arbitrator, propositions[fork_question_id].arbitrator, propositions[fork_question_id].bridge);

        newFm.init(payable(address(this)), address(newRealityETH), address(newBridgeToL2), (numGovernanceFreezes > 0), supplyAtFork, libForkManager, libForkableRealityETH, libBridgeToL2, address(0), 0);
        newFm.mint(address(newRealityETH), migrate_funds);

        if (yes_or_no) {
            childForkManager1 = ForkManager(newFm);
        } else {
            childForkManager2 = ForkManager(newFm);
        }

    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @param question_id The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitrationByFork(bytes32 question_id, uint256 max_previous)
    external returns (bool) {

        require(question_id != bytes32(uint256(0)), "Question ID is empty");
        require(isUnForked(), 'Already forked, call against the winning child');

        // TODO: Should we be using effectiveTotalSupply here instead of totalSupply???
        uint256 fork_cost = totalSupply * PERCENT_TO_FORK / 100;
        require(balanceOf[msg.sender] >= fork_cost, 'Not enough tokens');
        balanceOf[msg.sender] = balanceOf[msg.sender] - fork_cost;

        realityETH.notifyOfArbitrationRequest(question_id, msg.sender, max_previous);

        forkRequestUser = msg.sender;
        fork_question_id = question_id;

        forkTS = block.timestamp + FORK_TIME_SECS;
        supplyAtFork = totalSupply;

        auction = new Auction_ERC20();
        auction.init(fork_cost, forkTS);

        // As of the forkTS, anybody will be able to call deployFork
        // TODO: Can we deploy these ahead of the scheduled time and only initialize them when we're ready?

    }

    function isUnForked() 
    public view returns (bool) {
        return (forkTS == 0);
    }

    // TODO: Rename as this gives us started-but-unresolved, in plain English that's a subset of started
    function isForkingScheduled() 
    public view returns (bool) {
        return (forkTS > 0 && address(replacedByForkManager) == address(0x0));
    }

    function isForkingResolved() 
    public view returns (bool) {
        return (address(replacedByForkManager) != address(0x0));
    }

    function resolveFork() 
    external {
        require(isForkingScheduled(), 'Not planning to fork');
        require(!isForkingResolved(), 'Forking already resolved');
        require(block.timestamp >= forkTS, 'Too soon');
        auction.calculatePrice();
        if (auction.winner()) {
            replacedByForkManager = childForkManager1;
        } else {
            replacedByForkManager = childForkManager2;
        }
    }

    function isWinner() 
    public view returns (bool) {
        // Genesis fork manager
        if (address(parentForkManager) == address(0x0)) {
            return true;
        }
        ForkManager parentReplacement = parentForkManager.replacedByForkManager();
        if (address(parentReplacement) == address(0x0)) {
            // not yet resolved
            return false;
        }
        return (address(parentReplacement) == address(this));
    }

    function isLoser() 
    public view returns (bool) {
        if (address(parentForkManager) == address(0x0)) {
            // Genesis fork manager
            return false;
        }
        ForkManager parentReplacement = parentForkManager.replacedByForkManager();
        if (address(parentReplacement) == address(0x0)) {
            // not yet resolved
            return false;
        }
        return (address(parentReplacement) != address(this));
    }

    function disputeFee(bytes32 question_id) 
    public view returns (uint256) {
        return PERCENT_TO_FORK * effectiveTotalSupply() / 100;
    }

    // Governance (including adding and removing arbitrators from the whitelist) has two steps:
    // 1) Create question
    // 2) Complete operation (if proposition succeeded) or nothing if it failed

    // For time-sensitive operations, we also freeze any interested parties, so
    // 1) Create question
    // 2) Prove sufficient bond posted, freeze
    // 3) Complete operation or Undo freeze

    function beginAddArbitratorToWhitelist(address whitelist_arbitrator, address arbitrator_to_add) 
    external {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_add));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_ADD_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        require(propositions[question_id].proposition_type == PropositionType.NONE, "Proposition already exists");
        propositions[question_id] = ArbitratorProposition(PropositionType.ADD_ARBITRATOR, whitelist_arbitrator, arbitrator_to_add, address(0));
    }

    function beginRemoveArbitratorFromWhitelist(address whitelist_arbitrator, address arbitrator_to_remove) 
    external {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_remove));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_REMOVE_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        require(propositions[question_id].proposition_type == PropositionType.NONE, "Proposition already exists");
        propositions[question_id] = ArbitratorProposition(PropositionType.REMOVE_ARBITRATOR, whitelist_arbitrator, arbitrator_to_remove, address(0));
    }

    function beginUpgradeBridge(address new_bridge) 
    external {
        string memory question = _toString(abi.encodePacked(new_bridge));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_BRIDGE_UPGRADE, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        require(propositions[question_id].proposition_type == PropositionType.NONE, "Proposition already exists");
        propositions[question_id] = ArbitratorProposition(PropositionType.UPGRADE_BRIDGE, address(0), address(0), new_bridge);
    }

    // Verify that a question is still open with a minimum bond specified
    // This can be used to freeze operations pending the outcome of a governance question
    // TODO: An earlier bond should also be enough if you don't call this right away
    function _verifyMinimumBondPosted(bytes32 question_id, uint256 minimum_bond) 
    internal {
        require(!realityETH.isFinalized(question_id), "Question is already finalized, execute instead");
        require(realityETH.getBestAnswer(question_id) == bytes32(uint256(1)), "Current answer is not 1");
        require(realityETH.getBond(question_id) >= minimum_bond, "Bond not high enough");
    }

    function clearFailedGovernanceProposal(bytes32 question_id) 
    external {

        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not found or wrong type");
        require(propositions[question_id].proposition_type == PropositionType.UPGRADE_BRIDGE, "Not a bridge upgrade proposition");

        require(realityETH.resultFor(question_id) != bytes32(uint256(1)), "Proposition passed");

        if (governance_freeze_question_ids[question_id]) {
            delete(governance_freeze_question_ids[question_id]);
            numGovernanceFreezes--;
        }
    }

    // If you've sent a proposition to reality.eth and it passed without needing arbitration-by-fork, you can complete it by passing the details in here
    function executeBridgeUpgrade(bytes32 question_id) 
    external {

        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(propositions[question_id].proposition_type == PropositionType.UPGRADE_BRIDGE, "Not a bridge upgrade proposition");

        address new_bridge = propositions[question_id].bridge;
        require(new_bridge != address(0x0), "Proposition not recognized");
        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        // If we froze the bridges for this question, clear the freeze
        if (governance_freeze_question_ids[question_id]) {
            delete(governance_freeze_question_ids[question_id]);
            numGovernanceFreezes--;
        }
        delete(propositions[question_id]);

        bridgeToL2 = ZKBridgeToL2(new_bridge);
    }

    function numTokensRequiredToFreezeBridges()
    public returns (uint256) {
        return effectiveTotalSupply()/100 * PERCENT_TO_FREEZE;
    }

    function freezeBridges(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(propositions[question_id].proposition_type == PropositionType.UPGRADE_BRIDGE, "Not a bridge upgrade proposition");
        require(!governance_freeze_question_ids[question_id], "Already frozen");

        uint256 required_bond = numTokensRequiredToFreezeBridges();
        _verifyMinimumBondPosted(question_id, required_bond);
        governance_freeze_question_ids[question_id] = true;

        numGovernanceFreezes++;
    }

    function executeAddArbitratorToWhitelist(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(propositions[question_id].proposition_type == PropositionType.ADD_ARBITRATOR, "Not an add arbitrator proposition");
        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_add = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).addArbitrator.selector, arbitrator_to_add);
        bridgeToL2.requestExecute(whitelist_arbitrator, data, 0, Operations.QueueType.Deque, Operations.OpTree.Rollup);


        delete(propositions[question_id]);
    }

    function numTokensRequiredToFreezeArbitratorOnWhitelist() 
    public returns (uint256) {
        return effectiveTotalSupply()/100 * PERCENT_TO_FREEZE;
    }

    // If you're about to pass a proposition but you don't want bad things to happen in the meantime
    // ...you can freeze stuff by proving that you sent a reasonable bond.
    // TODO: Should we check the current answer to make sure the bond is for the remove answer not the keep answer?
    function freezeArbitratorOnWhitelist(bytes32 question_id) 
    external {

        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Not a remove arbitrator proposition");

        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_remove = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        uint256 required_bond = numTokensRequiredToFreezeArbitratorOnWhitelist();
        _verifyMinimumBondPosted(question_id, required_bond);

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(arbitrator_to_remove).freezeArbitrator.selector, arbitrator_to_remove);
        bridgeToL2.requestExecute(whitelist_arbitrator, data, 0, Operations.QueueType.Deque, Operations.OpTree.Rollup);
    }
    
    function executeRemoveArbitratorFromWhitelist(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Not a remove arbitrator proposition");

        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_remove = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        bridgeToL2.requestExecute(whitelist_arbitrator, data, 0, Operations.QueueType.Deque, Operations.OpTree.Rollup);

        delete(propositions[question_id]);
    }

    function executeUnfreezeArbitratorOnWhitelist(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Not a remove arbitrator proposition");

        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_remove = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        require(realityETH.resultFor(question_id) == bytes32(uint256(0)), "Proposition passed");

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).unfreezeArbitrator.selector, arbitrator_to_remove);
        bridgeToL2.requestExecute(whitelist_arbitrator, data, 0, Operations.QueueType.Deque, Operations.OpTree.Rollup);

        delete(propositions[question_id]);
    }

    // The WhitelistArbitrator is earning us money in fees.
    // However these are in a different token to the ForkManager's token.
    // This will burn some ForkManager tokens, giving the burner the right to get some of that token.
    // The order_id is an order they already made from an auction on the L2 system giving them the right buy at a set price.
    // If the order_id doesn't exist on L2 you'll lose the burned tokens but not get anything in return, bad luck.
    function executeTokenSale(WhitelistArbitrator wa, bytes32 order_id, uint256 num_gov_tokens)
    external {
        require(balanceOf[msg.sender] >= num_gov_tokens, "Not enough tokens");
        balanceOf[msg.sender] = balanceOf[msg.sender] - num_gov_tokens;
        bytes memory data = abi.encodeWithSelector(wa.executeTokenSale.selector, order_id, num_gov_tokens);
        bridgeToL2.requestExecute(address(wa), data, 0, Operations.QueueType.Deque, Operations.OpTree.Rollup);
    }

    function _toString(bytes memory data) 
    internal pure returns(string memory) {
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(2 + data.length * 2);
        str[0] = '0';
        str[1] = 'x';
        for (uint i = 0; i < data.length; i++) {
                str[2+i*2] = alphabet[uint(uint8(data[i] >> 4))];
                str[3+i*2] = alphabet[uint(uint8(data[i] & 0x0f))];
        }
        return string(str);
    }

    /// @notice Returns the address of a proxy based on the specified address
    /// @dev No initialization is done here
    /// @dev based on https://github.com/optionality/clone-factory
    function _deployProxy(address _target)
    internal returns (address result) {
        bytes20 targetBytes = bytes20(_target);
        assembly {
            let clone := mload(0x40)
            mstore(clone, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(clone, 0x14), targetBytes)
            mstore(add(clone, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            result := create(0, clone, 0x37)
        }
    }

    // This will return the bridges that should be used to manage assets
    function requiredBridges() 
    external returns (address bridge1, address bridge2) {

        // If something is frozen pending a governance decision, return zeros
        // This should be interpreted to mean no bridge can be trusted and transfers should stop.

        if (numGovernanceFreezes > 0) {
            return (address(0), address(0));
        }

        // If there was something frozen when we forked over something else, maintain the freeze until people have had time to recreate it
        if (initialGovernanceFreezeTimeout > 0 && block.timestamp < initialGovernanceFreezeTimeout) {
            return (address(0), address(0));
        }

        if (!isForkingScheduled()) {
            return (address(bridgeToL2), address(0));
        }

        if (isForkingResolved()) {
            return (address(0), address(0));
        } else {
            return(address(childForkManager1.bridgeToL2()), address(childForkManager2.bridgeToL2()));
        }

    }

    // Migrate tokens to the children after a fork
    // If you like you can ignore either of the forks and just burn your tokens
    // You would only do this if it will use more gas than it's worth, or is the result of a malicious upgrade.
    function migrateToChildren(uint256 num, bool ignore_yes, bool ignore_no) 
    external {
        require(isForkingResolved(), "Not forking");

        require(balanceOf[msg.sender] > num, "Not enough funds");
        balanceOf[msg.sender] = balanceOf[msg.sender] - num;
        totalSupply = totalSupply - num;

        if (!ignore_yes) {
            require(address(childForkManager1) != address(0), "Call deployFork first");
            childForkManager1.mint(msg.sender, num);
        }

        if (!ignore_no) {
            require(address(childForkManager2) != address(0), "Call deployFork first");
            childForkManager2.mint(msg.sender, num);
        }

    }

    function bid(uint8 _bid, uint256 _amount) 
    external {
        require(address(auction) != address(0), "Auction not under way");
        require(balanceOf[msg.sender] >= _amount, "Balance lower than bid amount"); 
        balanceOf[msg.sender] = balanceOf[msg.sender] - _amount;
        auction.bid(msg.sender, _bid, _amount);
    }

    function settleBid(uint256 bid_id, bool yes_or_no) 
    external {
        require(address(auction) != address(0), "Auction not under way");
        (address payee, uint256 due) = auction.clearAndReturnPayout(bid_id, yes_or_no);
        if (yes_or_no) {
            require(address(childForkManager1) != address(0), "Call deployFork first");
            childForkManager1.mint(payee, due);
        } else {
            require(address(childForkManager2) != address(0), "Call deployFork first");
            childForkManager2.mint(payee, due);
        }
    }

}
