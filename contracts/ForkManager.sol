pragma solidity ^0.4.25;

import './ForkableRealitioERC20.sol';
import './RealitioERC20.sol';
import './IArbitrator.sol';
import './IForkManager.sol';
import './WhitelistArbitrator.sol';
import './BridgeToL2.sol';

// An ERC20 token committed to a particular fork.
// If enough funds are committed, it can enter a forking state, which effectively creates a futarchic market between two competing ChainManager contracts, and therefore two competing L2 ledgers.
contract ForkManager is IArbitrator, IForkManager, RealitioERC20  {

    mapping(address => mapping(address => bytes32)) add_arbitrator_propositions;
    mapping(address => mapping(address => bytes32)) remove_arbitrator_propositions;
    mapping(address => bytes32) upgrade_bridge_propositions;

    string constant QUESTION_DELIM = "\u241f";
   
    // These are created by ForkableRealitioERC20 in its constructor
    uint256 ADD_ARBITRATOR_TEMPLATE_ID = 2147483648;
    uint256 REMOVE_ARBITRATOR_TEMPLATE_ID = 2147483649;
    uint256 BRIDGE_UPGRADE_TEMPLATE_ID = 2147483650;

    // 5% of total supply will prompt a fork.
    // Usually you'd do this as part of a reality.eth arbitration request which will fund you, although you don't have to.
    uint256 constant PERCENT_TO_FORK = 5;
    uint256 constant PERCENT_TO_FREEZE = 1;

    // Give people 1 week to pick a side.
    uint256 constant FORK_TIME_SECS = 604800; // 1 week
    uint32 constant ARB_DISPUTE_TIMEOUT = 604800; // 1 week
    uint32 constant GOVERNANCE_QUESTION_TIMEOUT = 604800;

    ChainManager public chainmanager;
    ForkableRealitioERC20 public realitio;
    BridgeToL2 public bridgeToL2;

    ForkManager public parentForkManager;

    address fork_requested_by_contract;
    bytes32 forked_over_question_id;

    ForkManager public childForkManager1;
    ForkManager public childForkManager2;

    mapping (bool => uint256) migratedBalances;

    ForkManager public replacedByForkManager;

    uint256 forkExpirationTS = 0;

	address arbitration_payer;
	bytes32 arbitrating_question_id;

    uint256 public totalSupply;

    mapping(bytes32 => bool) executed_questions;

    function init(address _parentForkManager, address _chainmanager, address _realitio, address _bridgeToL2) 
    external {
		require(address(chainmanager) == address(0), "You can only call init once");
		require(address(_chainmanager) != address(0), "ChainManager address must be supplied");
		require(address(_realitio) != address(0), "Realitio address must be supplied");
		require(address(_bridgeToL2) != address(0), "Bridge address must be supplied");

        parentForkManager = ForkManager(_parentForkManager); // 0x0 for genesis
		chainmanager = ChainManager(_chainmanager);
		realitio = ForkableRealitioERC20(_realitio);
        bridgeToL2 = BridgeToL2(_bridgeToL2);
    }

    function mint(address _to, uint256 _amount) 
    external {
        require(msg.sender == address(parentForkManager), "Only our parent can mint tokens");
        // TODO check events
        totalSupply = totalSupply.add(_amount);
        balanceOf[_to] = balanceOf[_to].add(_amount);
    }

    function migrateToChild(bool yes_or_no, uint256 amount) 
    external {
        require(amount > balanceOf[msg.sender], "Balance too low");
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(amount);
        totalSupply = totalSupply.sub(amount);
        IForkManager fm = yes_or_no ? IForkManager(childForkManager1) : IForkManager(childForkManager2); 
        fm.mint(msg.sender, amount);
        migratedBalances[yes_or_no] = migratedBalances[yes_or_no].add(amount);
    }

	// Function to clone ourselves.
	// This in turn clones the realitio instance and the ChainManager.
	// An arbitrator fork will create this for both forks.
	// A governance fork will use the specified contract for one of the options.
	// It can have its own setup logic if you want to change the Realitio or ChainManager code.
	// TODO: Maybe better to find the uppermost library address instead of delegating proxies to delegating proxies?
    function _cloneForFork() 
    internal returns (IForkManager) {
        IForkManager newFm = IForkManager(_deployProxy(this));
		ChainManager newCm = ChainManager(_deployProxy(chainmanager)); // TODO: May need other init steps
        BridgeToL2 newBridgeToL2 = BridgeToL2(_deployProxy(bridgeToL2));
//TODO
        //newBridgeFromL2ToL1 = BridgeFromL2(_deployProxy(bridgeFromL2ToL1));
        newBridgeToL2.setParent(this);
        //newBridgeFromL2ToL1.setParent(this);
		ForkableRealitioERC20 newRealitio = ForkableRealitioERC20(_deployProxy(realitio));
		newRealitio.setParent(IForkableRealitio(realitio));
		newRealitio.setToken(newFm);
		newRealitio.init();
		newFm.init(address(this), address(newCm), address(newRealitio), address(bridgeToL2));
		return newFm;
    }

    /// @notice Request arbitration, freezing the question until we send submitAnswerByArbitrator
    /// @param question_id The question in question
    /// @param max_previous If specified, reverts if a bond higher than this was submitted after you sent your transaction.
    function requestArbitrationERC20(bytes32 question_id, uint256 max_previous)
    external returns (bool) {

        require(isUnForked(), 'Already forked, call against the winning child');

        uint256 fork_cost = totalSupply * PERCENT_TO_FORK / 100;
        require(balanceOf[msg.sender] > fork_cost, 'Not enough tokens');
        balanceOf[msg.sender] = balanceOf[msg.sender].sub(fork_cost);

		realitio.notifyOfArbitrationRequest(question_id, msg.sender, max_previous);

        childForkManager1 = ForkManager(_cloneForFork());
        childForkManager2 = ForkManager(_cloneForFork());

        uint256 migrate_funds = realitio.getCumulativeBonds(question_id);

        childForkManager1.mint(childForkManager1.realitio(), migrate_funds);
        childForkManager2.mint(childForkManager2.realitio(), migrate_funds);

        migratedBalances[true] = migratedBalances[true].add(migrate_funds);
        migratedBalances[false] = migratedBalances[false].add(migrate_funds);

        fork_requested_by_contract = msg.sender;
        forked_over_question_id = question_id;

        forkExpirationTS = block.timestamp + FORK_TIME_SECS;

        // TODO: Do we need to tell anyone on L2 about this? Maybe not since it should already be frozen
        // notifyOfFork(question_id);

    }

    function assignWinnerAndSubmitAnswerByArbitrator( bytes32 question_id, bytes32 answer, address payee_if_wrong, bytes32 last_history_hash, bytes32 last_answer, address last_answerer )
    external {
        require(question_id != bytes32(0), "Question ID is empty");
        require(question_id == forked_over_question_id, "You can only arbitrate a question we forked over");
        require(answer == bytes32(0) || answer == bytes32(1), "Answer can only be 1 or 2");
        IForkManager fm = (answer == bytes32(0)) ? childForkManager1 : childForkManager2;
        ForkableRealitioERC20 r = ForkableRealitioERC20(fm.realitio());

        r.assignWinnerAndSubmitAnswerByArbitrator(question_id, answer, payee_if_wrong, last_history_hash, last_answer, last_answerer);

        // Removed for now  - we should do this asynchronously somewhere as it also happens in non-arbitrated cases
        // If this is an arbitration question, notify the ledger waiting to unfreeze on L2
        // TODO: Should this come from the child forkmanager?
        // bytes memory data1 = abi.encodeWithSelector(notify_who.handleFork.selector, question_id, bytes32(1));
        // fm.bridgeToL2().requireToPassMessage(notify_who, data1);
    }

    function isUnForked() 
    public returns (bool) {
        return (forkExpirationTS == 0);
    }

    function isForking() 
    public returns (bool) {
        return (forkExpirationTS > 0 && replacedByForkManager == address(0x0));
    }

    function isForkingResolved() 
    public returns (bool) {
        return (replacedByForkManager != address(0x0));
    }

    function currentBestForkManager() 
    external returns (ForkManager) {
        if (!isForkingResolved()) {
            return this;
        }
        return replacedByForkManager.currentBestForkManager();
    }

    function resolveFork() 
    external {
        require(isForkingResolved(), 'Not forking');
        require(block.timestamp > forkExpirationTS, 'Too soon');
        if (childForkManager1.totalSupply() > childForkManager2.totalSupply()) {
            replacedByForkManager = childForkManager1;
        } else {
            replacedByForkManager = childForkManager2;
        }
    }

    function isWinner() 
    public constant returns (bool) {
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
    public constant returns (bool) {
        if (address(parentForkManager) == address(0x0)) {
            // Genesis fork manager
            return false;
        }
        ForkManager parentReplacement = parentForkManager.replacedByForkManager();
        if (address(parentReplacement) == address(0x0)) {
            // not yet resolved
            return false;
        }
        return (address(parentReplacement) == address(this));
    }

    // TODO: Check what happens right after we fork
    function disputeFee(bytes32 question_id) 
    public constant returns (uint256) {
        return PERCENT_TO_FORK * totalSupply / 100;
    }

    function _verifyPropositionPassed(uint256 template_id, string memory question, uint32 opening_ts, address question_creator) {
        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));
        bytes32 question_id = keccak256(abi.encodePacked(content_hash, this, GOVERNANCE_QUESTION_TIMEOUT, msg.sender, uint256(0)));
        require(realitio.resultFor(question_id) == bytes32(1), "Governance proposal did not pass");
    }

    // Verify that a question is still open with a minimum bond specified
    // This can be used to freeze operations pending the outcome of a governance question
    function _verifyMinimumBondPosted(uint256 template_id, string memory question, uint32 opening_ts, address question_creator, uint256 minimum_bond) 
    internal {
        bytes32 content_hash = keccak256(abi.encodePacked(template_id, opening_ts, question));
        bytes32 question_id = keccak256(abi.encodePacked(content_hash, this, GOVERNANCE_QUESTION_TIMEOUT, msg.sender, uint256(0)));
        require(!realitio.isFinalized(question_id), "Question is already finalized, execute instead");
        require(realitio.getBestAnswer(question_id) == bytes32(1), "Current answer is not 1");
        require(realitio.getBond(question_id) >= minimum_bond, "Bond not high enough");
    }

    // If you've sent a proposition to reality.eth and it passed without needing arbitration, you can complete it by passing the details in here
    function completeBridgeUpgrade(address new_bridge, uint32 opening_ts, address question_asker) 
    external {
        string memory question = _toString(abi.encodePacked(new_bridge));
        _verifyPropositionPassed(BRIDGE_UPGRADE_TEMPLATE_ID, question, opening_ts, question_asker);
        bridgeToL2 = BridgeToL2(new_bridge);
    }

    // Governance has 2 steps
    // 1) Create question
    // 2) Complete operation (if proposition succeeded) or nothing if it failed

    // For time-sensitive operations, we also freeze any interested parties, so
    // 1) Create question
    // 2) Prove bond posted, freeze
    // 3) Complete operation or Undo freeze


    function beginAddArbitratorToWhitelist(WhitelistArbitrator whitelist_arbitrator, IArbitrator arbitrator_to_add) {
        require(add_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_add] == bytes32(0x0), "Existing proposition must be completed first");

        //TODO: Work out how the approve flow works
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_add));
        // TODO: Can an arbitrator be denied then approved then added again? If so we need to track the nonce or opening time
        add_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_add] = realitio.askQuestion(ADD_ARBITRATOR_TEMPLATE_ID, question, address(this), ARB_DISPUTE_TIMEOUT, 0, 0);
    }

    function completeAddArbitratorToWhitelist(address whitelist_arbitrator, address arbitrator_to_add, uint32 opening_ts, address question_creator) {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_add));
        _verifyPropositionPassed(ADD_ARBITRATOR_TEMPLATE_ID, question, opening_ts, question_creator);
        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).addArbitrator.selector);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        delete add_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_add];
    }

    // If you're about to pass a proposition but you don't want bad things to happen in the meantime
    // ...you can freeze stuff by proving that you sent a reasonable bond.
    // TODO: Is the claim fee sufficient for this? You could grief by posting a bond then claiming it yourself.
    function freezeArbitratorOnWhitelist(address whitelist_arbitrator, address arbitrator_to_remove, uint32 opening_ts, address question_creator) {
        // Require a sufficient bond to have been posted
        uint256 required_bond = totalSupply/100 * PERCENT_TO_FREEZE;
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_remove));
        _verifyMinimumBondPosted(REMOVE_ARBITRATOR_TEMPLATE_ID, question, opening_ts, question_creator, required_bond);
        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).freezeArbitrator.selector);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
    }
    
    function beginRemoveArbitratorFromWhitelist(WhitelistArbitrator whitelist_arbitrator, IArbitrator arbitrator_to_remove) {

        require(remove_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_remove] == bytes32(0x0), "Existing proposition must be completed first");

        //TODO: Work out how the approve flow works
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_remove));
        // TODO: Can an arbitrator be added then removed then added again? If so we need to track the nonce
        remove_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_remove] = realitio.askQuestion(REMOVE_ARBITRATOR_TEMPLATE_ID, question, address(this), ARB_DISPUTE_TIMEOUT, 0, 0);
    }

    function completeRemoveArbitratorFromWhitelist(address whitelist_arbitrator, address arbitrator_to_remove, uint32 opening_ts, address question_asker) {
        string memory question = _toString(abi.encodePacked(whitelist_arbitrator, QUESTION_DELIM, arbitrator_to_remove));
        _verifyPropositionPassed(REMOVE_ARBITRATOR_TEMPLATE_ID, question, opening_ts, question_asker);
        bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector);
        bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        delete remove_arbitrator_propositions[whitelist_arbitrator][arbitrator_to_remove];
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

}
