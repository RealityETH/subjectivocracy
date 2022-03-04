// SPDX-License-Identifier: GPL-3.0-only

pragma solidity ^0.8.10;

import './IERC20.sol';
import './ERC20.sol';

import './ForkableRealityETH_ERC20.sol';
import './Arbitrator.sol';
import './WhitelistArbitrator.sol';
import './BridgeToL2.sol';

contract ForkManager is Arbitrator, IERC20, ERC20 {

    //uint256 public totalSupply;

    // The way we access L2
    BridgeToL2 public bridgeToL2;

    // If we fork, our parent will be able to tell us to mint funds
    ForkManager public parentForkManager;

    // We use a special Reality.eth instance for governance and arbitration whitelist management
    ForkableRealityETH_ERC20 public realityETH;

    // When we try to add or remove an arbitrator or upgrade the bridge, use this timeout for the reality.eth question
    uint32 constant REALITY_ETH_TIMEOUT = 604800; // 1 week

    // The standard reality.eth delimiter for questions with multiple arguments
    string constant QUESTION_DELIM = "\u241f";
   
    // These are created by ForkableRealityETH_ERC20 in its constructor
    uint256 TEMPLATE_ID_ADD_ARBITRATOR = 2147483648;
    uint256 TEMPLATE_ID_REMOVE_ARBITRATOR = 2147483649;
    uint256 TEMPLATE_ID_BRIDGE_UPGRADE = 2147483650;

    enum PropositionType {
        NONE,
        ADD_ARBITRATOR,
        REMOVE_ARBITRATOR,
        UPGRADE_BRIDGE
    }

    // We act as the arbitrator for the ForkableRealityETH_ERC20 instance. We arbitrate by forking.
    // Our fee to arbitrate (ie fork) will be 5% of total supply.
    // Usually you'd do this as part of a reality.eth arbitration request which will fund you, although you don't have to.
    uint256 constant PERCENT_TO_FORK = 5;

    // 1% of total supply can freeze the bridges while we ask a governance question
    uint256 constant PERCENT_TO_FREEZE = 1;

    // In a fork, give people 1 week to pick a side. After that, we will declare one side the "winner".
    uint256 constant FORK_TIME_SECS = 604800; // 1 week

    // If we fork over one question, but bridges are already frozen over another, we reset any outstanding questions on child forks and you have to ask them again.
    // However we keep the bridges frozen to give you time to recreate the question over which you froze the bridges.
    // After this time, if nobody recreated them, they will be automatically unfrozen
    uint256 constant POST_FORK_FREEZE_TIMEOUT = 604800;

    // A list of questions that have been used to freeze governance
    mapping(bytes32 => bool) governance_freeze_question_ids;
    uint256 numGovernanceFreezes;

    // The reality.eth question over which we forked. This should be migrated so you can claim bonds on each fork.
    bytes32 fork_question_id;

    // The timestamp when were born in a fork. 0 for the genesis ForkManager.
    uint256 forked_from_parent_ts = 0;

    // Governance questions will be cleared when we fork, if you still care about them you can ask them again.
    // However, if we forked over arbitration but had some unresolved governance questions, we stay frozen initially to give people time to recreate them
    uint256 initial_governance_freeze_timeout;

    // If we fork we will produce two children
    ForkManager public childForkManager1;
    ForkManager public childForkManager2;

    // Once the fork is resolved you can set the winner
    ForkManager public replacedByForkManager;

    // Having deployed each fork, you can move funds into it
    uint256 public amountMigrated1;
    uint256 public amountMigrated2;

    // The total supply of the parent when our fork was born.
    // We use this as a freeze threshold when it's too early to use our own supply because people are still migrating funds.
    uint256 public parentSupply;

    // The total supply we had when we forked
    // Kept so we can tell our children what to set as their parentSupply
    uint256 supplyAtFork;

    // The deadline for moving funds, when we will decide which fork won.
    uint256 forkExpirationTS = 0;

    // Reality.eth questions for propositions we may be asked to rule on
    struct ArbitratorProposition{
        PropositionType proposition_type;
        address whitelist_arbitrator;
        address arbitrator;
        address bridge;
    }
    mapping(bytes32 => ArbitratorProposition) propositions;

    // Libraries used when creating the child contracts in a fork
    // In theory we could query the current proxies for this information.
    // In practice we'd have to either use ContractProbe which looks complex or modify the generic proxy contract to be able to return its library address
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
        bridgeToL2 = BridgeToL2(_bridgeToL2);

        if (_has_governance_freeze) {
            initial_governance_freeze_timeout = block.timestamp + POST_FORK_FREEZE_TIMEOUT;
        }
        parentSupply = _parentSupply;
        
        // Genesis
        if (_parentForkManager == address(0x0)) {
            totalSupply = _initialSupply;
            balanceOf[_initialRecipient] = _initialSupply;
        } else {
            forked_from_parent_ts = block.timestamp;
        }

    }

    // This could be done in init but it already has a lot of parameters
    function importProposition(bytes32 question_id, PropositionType proposition_type, address whitelist_arbitrator, address arbitrator, address new_bridge) 
    external {
        require(address(libForkManager) == address(0), "Must be run before init");
        propositions[question_id] = ArbitratorProposition(proposition_type, whitelist_arbitrator, arbitrator, new_bridge);
    }

    // When forked, the ultimate totalSupply is not known until migration is complete, but we want to be able to freeze things.
    // Start with an approximation based on how many tokens the parent had.
    function effectiveTotalSupply()
    internal view returns (uint256) {
        if (forked_from_parent_ts == 0 || (block.timestamp - forked_from_parent_ts > FORK_TIME_SECS)) {
            return totalSupply;
        } else {
            uint256 halfParent = parentSupply / 2;
            return (halfParent > totalSupply) ? halfParent : totalSupply;
        }
    }

    function mint(address _to, uint256 _amount) 
    external {
        require(msg.sender == address(parentForkManager), "Only our parent can mint tokens");
        totalSupply = totalSupply + _amount;
        balanceOf[_to] = balanceOf[_to] + _amount;
        emit Transfer(address(0), _to, _amount);
    }

    // Function to clone ourselves.
    // This in turn clones the realityETH instance and the bridge.
    // An arbitrator fork will create this for both forks.
    // A governance fork will use the specified contract for one of the options.
    // It can have its own setup logic if you want to change the RealityETH or bridge code.
    function deployFork(bool yes_or_no, bytes32 last_history_hash, bytes32 last_answer, address last_answerer, uint256 last_bond) 
    external {
        bytes32 result;
        if (yes_or_no) {
            require(address(childForkManager1) == address(0), "Already migrated");
            result = bytes32(uint256(1));
        } else {
            require(address(childForkManager2) == address(0), "Already migrated");
            result = bytes32(uint256(0));
        }

        // TODO: Verify that last_answerer and last_answerer match the current history hash 
        // bytes32 history_hash = realityETH.getHistoryHash(fork_question_id);
        // require(history_hash == keccak256(abi.encodePacked(last_history_hash, last_answerer, last_bond, last_answerer, false)), "Wrong parameters supplied for last answer");

        require(fork_question_id != bytes32(uint256(0)), "Fork not initiated");
        require(block.timestamp < forkExpirationTS, "Too late to deploy a fork");

        uint256 migrate_funds = realityETH.getCumulativeBonds(fork_question_id);

        ForkManager newFm = ForkManager(payable(_deployProxy(libForkManager)));

        BridgeToL2 newBridgeToL2;

        // If this is a bridge upgrade proposition, we use the specified bridge for the yes fork.
        // Otherwise we just clone the current one.
        if (yes_or_no && propositions[fork_question_id].proposition_type == PropositionType.UPGRADE_BRIDGE) {
            newBridgeToL2 = BridgeToL2(propositions[fork_question_id].bridge);
        } else {
            newBridgeToL2 = BridgeToL2(_deployProxy(libBridgeToL2));
        }

        // If it's a new bridge should let us call these without error
        newBridgeToL2.setParent(address(this));
        newBridgeToL2.init();

        ForkableRealityETH_ERC20 newRealityETH = ForkableRealityETH_ERC20(_deployProxy(libForkableRealityETH));
        newRealityETH.init(IERC20(newFm), address(realityETH), fork_question_id);

        address payee = last_answer == result ? last_answerer : address(this);
        newRealityETH.submitAnswerByArbitrator(fork_question_id, result, payee);

        newFm.importProposition(fork_question_id, propositions[fork_question_id].proposition_type, propositions[fork_question_id].whitelist_arbitrator, propositions[fork_question_id].arbitrator, propositions[fork_question_id].bridge);

        newFm.init(payable(address(this)), address(newRealityETH), address(bridgeToL2), (numGovernanceFreezes > 0), supplyAtFork, libForkManager, libForkableRealityETH, libBridgeToL2, address(0), 0);
        newFm.mint(address(newRealityETH), migrate_funds);


        // TODO: Do we need to migrate propositions here?
        //newFm.migrateProposition

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

        uint256 fork_cost = totalSupply * PERCENT_TO_FORK / 100;
        require(balanceOf[msg.sender] >= fork_cost, 'Not enough tokens');
        balanceOf[msg.sender] = balanceOf[msg.sender] - fork_cost;

        realityETH.notifyOfArbitrationRequest(question_id, msg.sender, max_previous);

        fork_question_id = question_id;

        forkExpirationTS = block.timestamp + FORK_TIME_SECS;
        supplyAtFork = totalSupply;

        // Anybody can now call deployFork() for each fork

    }

    function isUnForked() 
    public view returns (bool) {
        return (forkExpirationTS == 0);
    }

    function isForkingStarted() 
    public view returns (bool) {
        return (forkExpirationTS > 0 && address(replacedByForkManager) == address(0x0));
    }

    function isForkingResolved() 
    public view returns (bool) {
        return (address(replacedByForkManager) != address(0x0));
    }

    function resolveFork() 
    external {
        require(isForkingStarted(), 'Not forking');
        require(!isForkingResolved(), 'Forking already resolved');
        require(block.timestamp > forkExpirationTS, 'Too soon');
        if (amountMigrated1 > amountMigrated2) {
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
    // 2) Prove bond posted, freeze
    // 3) Complete operation or Undo freeze

    function beginAddArbitratorToWhitelist(address whitelist_arbitrator, address arbitrator_to_add) 
    external {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_add));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_ADD_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        propositions[question_id] = ArbitratorProposition(PropositionType.ADD_ARBITRATOR, whitelist_arbitrator, arbitrator_to_add, address(0));
    }

    function beginRemoveArbitratorFromWhitelist(address whitelist_arbitrator, address arbitrator_to_remove) 
    external {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_remove));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_REMOVE_ARBITRATOR, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        propositions[question_id] = ArbitratorProposition(PropositionType.REMOVE_ARBITRATOR, whitelist_arbitrator, arbitrator_to_remove, address(0));
    }

    function beginUpgradeBridge(address new_bridge) 
    external {
        string memory question = _toString(abi.encodePacked(new_bridge));
        bytes32 question_id = realityETH.askQuestion(TEMPLATE_ID_BRIDGE_UPGRADE, question, address(this), REALITY_ETH_TIMEOUT, uint32(block.timestamp), 0);
        propositions[question_id] = ArbitratorProposition(PropositionType.UPGRADE_BRIDGE, address(0), address(0), new_bridge);
    }

    // Verify that a question is still open with a minimum bond specified
    // This can be used to freeze operations pending the outcome of a governance question
    function _verifyMinimumBondPosted(bytes32 question_id, uint256 minimum_bond) 
    internal {
        require(!realityETH.isFinalized(question_id), "Question is already finalized, execute instead");
        require(realityETH.getBestAnswer(question_id) == bytes32(uint256(1)), "Current answer is not 1");
        require(realityETH.getBond(question_id) >= minimum_bond, "Bond not high enough");
    }

    function clearFailedGovernanceProposal(bytes32 question_id) 
    external {

        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not found or wrong type");
        require(realityETH.resultFor(question_id) != bytes32(uint256(1)), "Proposition passed");

        if (governance_freeze_question_ids[question_id]) {
            delete(governance_freeze_question_ids[question_id]);
            numGovernanceFreezes--;
        }
    }

    // If you've sent a proposition to reality.eth and it passed without needing arbitration, you can complete it by passing the details in here
    function executeBridgeUpgrade(bytes32 question_id) 
    external {

        address new_bridge = propositions[question_id].bridge;
        require(new_bridge != address(0x0), "Proposition not recognized");
        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        // If we froze the bridges for this question, clear the freeze
        if (governance_freeze_question_ids[question_id]) {
            delete(governance_freeze_question_ids[question_id]);
            numGovernanceFreezes--;
        }
        delete(propositions[question_id]);

        bridgeToL2 = BridgeToL2(new_bridge);
    }


    function freezeBridges(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type != PropositionType.NONE, "Proposition not recognized");
        require(!governance_freeze_question_ids[question_id], "Already frozen");

        uint256 required_bond = effectiveTotalSupply()/100 * PERCENT_TO_FREEZE;
        _verifyMinimumBondPosted(question_id, required_bond);
        governance_freeze_question_ids[question_id] = true;

        numGovernanceFreezes++;
    }

    function executeAddArbitratorToWhitelist(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type == PropositionType.ADD_ARBITRATOR, "Not an add arbitrator proposition");
        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_add = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).addArbitrator.selector, arbitrator_to_add);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);

        delete(propositions[question_id]);
    }

    // If you're about to pass a proposition but you don't want bad things to happen in the meantime
    // ...you can freeze stuff by proving that you sent a reasonable bond.
    // TODO: Should we check the current answer to make sure the bond is for the remove answer not the keep answer?
    function freezeArbitratorOnWhitelist(bytes32 question_id) 
    external {

        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Not a remove arbitrator proposition");

        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_remove = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        uint256 required_bond = effectiveTotalSupply()/100 * PERCENT_TO_FREEZE;
        _verifyMinimumBondPosted(question_id, required_bond);

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(arbitrator_to_remove).freezeArbitrator.selector, arbitrator_to_remove);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
    }
    
    function executeRemoveArbitratorFromWhitelist(bytes32 question_id) 
    external {
        require(propositions[question_id].proposition_type == PropositionType.REMOVE_ARBITRATOR, "Not a remove arbitrator proposition");

        address whitelist_arbitrator = propositions[question_id].whitelist_arbitrator;
        address arbitrator_to_remove = propositions[question_id].arbitrator;

        require(whitelist_arbitrator != address(0x0), "Proposition not recognized");

        require(realityETH.resultFor(question_id) == bytes32(uint256(1)), "Proposition did not pass");

        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);

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
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);

        delete(propositions[question_id]);
    }

    function executeTokenSale(WhitelistArbitrator wa, bytes32 order_id, uint256 num_gov_tokens)
    external {
        require(balanceOf[msg.sender] >= num_gov_tokens, "Not enough tokens");
        balanceOf[msg.sender] = balanceOf[msg.sender] - num_gov_tokens;
        bytes memory data = abi.encodeWithSelector(wa.executeTokenSale.selector, order_id, num_gov_tokens);
        bridgeToL2.requireToPassMessage(address(wa), data, 0);
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
    external returns (address[] memory) {

        address[] memory addrs;

        // If something is frozen pending a governance decision, return an empty array.
        // This should be interpreted to mean no bridge can be trusted and transfers should stop.

        if (numGovernanceFreezes > 0) {
            return addrs;
        }

        // If there was something frozen when we forked over something else, maintain the freeze until people have had time to recreate it
        if (initial_governance_freeze_timeout > 0 && block.timestamp < initial_governance_freeze_timeout) {
            return addrs;
        }

        // If there's an unresolved fork, we need the consent of both child bridges before performing an operation
        if (isForkingStarted()) {
            if (isForkingResolved()) {
                return addrs;
            } else {
                // NB These may be empty if uninitialized
                addrs[0] = address(childForkManager1.bridgeToL2());
                addrs[1] = address(childForkManager2.bridgeToL2());
            }
        } else {
            addrs[0] = address(bridgeToL2);
        }

        return addrs;

    }

    function pickFork(bool yes_or_no, uint256 num) 
    external {
        require(isForkingStarted(), "Not forking");
        require(!isForkingResolved(), "Too late");
        require(balanceOf[msg.sender] > num, "Not enough funds");
        balanceOf[msg.sender] = balanceOf[msg.sender] - num;
        totalSupply = totalSupply - num;
        if (yes_or_no) {
            amountMigrated1 = amountMigrated1 + num;
            require(address(childForkManager1) != address(0), "Call deployFork first");
            childForkManager1.mint(msg.sender, num);
        } else {
            amountMigrated2 = amountMigrated2 + num;
            require(address(childForkManager2) != address(0), "Call deployFork first");
            childForkManager2.mint(msg.sender, num);
        }
    }

}
