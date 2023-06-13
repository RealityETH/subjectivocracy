import unittest
from unittest import TestCase, main
from eth_utils import decode_hex, encode_hex
#from ethereum.tools.tester import TransactionFailed, ABIContract

from eth_tester.exceptions import TransactionFailed

from eth_keys import keys
import time
from hashlib import sha256

from web3 import Web3, EthereumTesterProvider

import json
import bitcoin
import os

import time

from eth_tester import EthereumTester, PyEVMBackend
from eth_tester import EthereumTester as t

import copy

# Contracts:
# Arbitrator.bin  ERC20.bin  ForkManager.bin  ForkableRealityETH_ERC20.bin  RealityETH_ERC20-3.0.bin  TokenBridge.bin  WhitelistArbitrator.bin BridgeToL2.bin

# Command-line flag to skip tests we're not working on
WORKING_ONLY = (int(os.environ.get('WORKING_ONLY', 0)) == 1)
REALITYETH_CONTRACT = 'RealityETH_ERC20-3.0'

NULL_BYTES = "0x000000000000000000000000000000000000000000000000000000000000000"

bits = REALITYETH_CONTRACT.split('-')
VERNUM = float(bits[1])
if "ERC20" in REALITYETH_CONTRACT:
    ERC20 = True
else:
    ERC20 = False

print("Version is "+str(VERNUM))

if VERNUM >= 2.1:
    CLAIM_FEE = 40
else:
    CLAIM_FEE = 0

DEPLOY_GAS = 8000000

# reality.eth Question struct
QINDEX_CONTENT_HASH = 0
QINDEX_ARBITRATOR = 1
QINDEX_OPENING_TS = 2
QINDEX_STEP_DELAY = 3
QINDEX_FINALIZATION_TS = 4
QINDEX_IS_PENDING_ARBITRATION = 5
QINDEX_BOUNTY = 6
QINDEX_BEST_ANSWER = 7
QINDEX_HISTORY_HASH = 8
QINDEX_BOND = 9
QINDEX_MIN_BOND = 10

# WhitelistArbitrator ArbitrationRequest struct
WAINDEX_ARBITRATOR = 0
WAINDEX_PAYER = 1
WAINDEX_BOUNTY = 2
WAINDEX_MSG_HASH = 3
WAINDEX_FINALIZE_TX = 4

ANSWERED_TOO_SOON_VAL = "0xfffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe"
FORKMANAGER_SPECIAL_ADDRESS = "0x00000000000000000000000000000000f0f0F0F0"

TEMPLATE_ID_ADD_ARBITRATOR = 2147483648;
TEMPLATE_ID_REMOVE_ARBITRATOR = 2147483649;
TEMPLATE_ID_BRIDGE_UPGRADE = 2147483650;
QUESTION_DELIM = "\u241f";

def calculate_answer_hash(answer, nonce):
    if answer[:2] == "0x":
        raise Exception("hash functions expect bytes for bytes32 parameters")
    if not isinstance(nonce, int):
        raise Exception("hash functions expect int for uint256 parameters")
    return Web3.solidity_keccak(['bytes32', 'uint256'], [answer, nonce])

def calculate_commitment_id(question_id, answer_hash, bond):
    if question_id[:2] == "0x":
        raise Exception("hash functions expect bytes for bytes32 parameters")
    if answer_hash[:2] == "0x":
        raise Exception("hash functions expect bytes for bytes32 parameters")
    if not isinstance(bond, int):
        raise Exception("hash functions expect int for uint256 parameters")
    #return decode_hex(keccak_256(question_id + answer_hash + decode_hex(hex(bond)[2:].zfill(64))).hexdigest())
    return Web3.solidity_keccak(['bytes32', 'bytes32', 'uint256'], [question_id, answer_hash, bond])

def calculate_content_hash(template_id, question_str, opening_ts):
    return Web3.solidity_keccak(['uint256', 'uint32', 'string'], [template_id, opening_ts, question_str])

def calculate_question_id(cntrct, template_id, question_str, arbitrator, timeout, opening_ts, nonce, sender, min_bond):
    content_hash = calculate_content_hash(template_id, question_str, opening_ts)
    if VERNUM >= 3:
        return Web3.solidity_keccak(['bytes32', 'address', 'uint32', 'uint256', 'address', 'address', 'uint256'], [content_hash, arbitrator, timeout, min_bond, cntrct, sender, nonce])
    else:
        return Web3.solidity_keccak(['bytes32', 'address', 'uint32', 'address', 'uint256'], [content_hash, arbitrator, timeout, sender, nonce])

def calculate_history_hash(last_history_hash, answer_or_commitment_id, bond, answerer, is_commitment):
    return Web3.solidity_keccak(['bytes32', 'bytes32', 'uint256', 'address', 'bool'], [last_history_hash, answer_or_commitment_id, bond, answerer, is_commitment])

def from_question_for_contract(txt):
    return txt

def to_answer_for_contract(txt):
    # to_answer_for_contract(("my answer")),
    return decode_hex(hex(txt)[2:].zfill(64))

def from_answer_for_contract(txt):
    return int(encode_hex(txt), 16)

def subfee(bond):
    if CLAIM_FEE == 0:
        return bond
    else:
        fee = CLAIM_FEE
        return int(bond - int(bond/fee))

class TestRealitio(TestCase):

    L2_ALICE = None
    L2_BOB = None
    L2_CHARLIE = None
    L2_DAVE = None

    # Creates a question and answers it to create a balance that can be withdrawn
    # NB This calls _issueTokens which alters approved, so you may need to reset it 
    def _setup_balance(self, acct, amt):

        fee = self.rc0.functions.arbitrator_question_fees(self.arb0.address).call()
        self.assertEqual(fee, 100)

        self._issueTokens(self.l2token1, acct, amt+fee, amt+fee)

        starting_bal = self.rc0.functions.balanceOf(acct).call()

        bond = 1

        txid = self.rc0.functions.askQuestionERC20(
            0,
            "my question _setup_balance",
            self.arb0.address,
            30,
            0,
            0
            ,(amt + fee - bond)
        ).transact(self._txargs(gas=300000, sender=acct))
        self.raiseOnZeroStatus(txid)

        qid = calculate_question_id(self.rc0.address, 0, "my question _setup_balance", self.arb0.address, 30, 0, 0, acct, 0)
        q = self.rc0.functions.questions(qid).call()
        self.assertEqual(q[QINDEX_BOUNTY], (amt - bond))

        st = self.submitAnswerReturnUpdatedState( None, qid, 1002, 0, bond, acct, False, False, False, None)
        q = self.rc0.functions.questions(qid).call()
        self.assertEqual(q[QINDEX_BOND], (bond))
        self.assertEqual(q[QINDEX_BEST_ANSWER], to_answer_for_contract(1002))

        self.l2web3.testing.mine()
        self._advance_clock(33)
        self.l2web3.testing.mine()

        self.rc0.functions.claimWinnings(qid, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        ending_bal = self.rc0.functions.balanceOf(acct).call()

        self.assertEqual(amt, ending_bal - starting_bal)



    def assertZeroStatus(self, txid, msg=None):
        self.assertEqual(self.l2web3.eth.get_transaction_receipt(txid)['status'], 0, msg)

    # Sometimes we seem to get a zero status receipt with no exception raised
    # Not sure if this is what's supposed to happen, but call this in the with block to make sure we get an exception 
    def raiseOnZeroStatus(self, txid, w3):
        if w3.eth.get_transaction_receipt(txid)['status'] == 0:
            #print(self.l2web3.eth.get_transaction_receipt(txid))
            raise TransactionFailed

    def _block_timestamp(self, web3 = None):
        if web3 is None:
            web3 = self.l2web3
        return web3.provider.ethereum_tester.get_block_by_number('pending')['timestamp']

    def _advance_clock(self, secs, web3 = None):
        if web3 is None:
            web3 = self.l2web3
        ts = self._block_timestamp(web3)
        web3.provider.ethereum_tester.time_travel(ts+secs)
        ts2 = self._block_timestamp(web3)
        web3.testing.mine()
        self.assertNotEqual(ts, ts2)

    def _txargs(self, val=0, gas=None, sender=None):
        standard_tx = self.standard_tx

        standard_tx['value'] = val

        if gas is not None:
            standard_tx['gas'] = gas

        if sender is None:
            standard_tx['from'] = self.l2web3.eth.accounts[0]
        else:
            standard_tx['from'] = sender

        return standard_tx

    def _issueTokens(self, token, addr, issued, approved):
        txid = token.functions.mint(addr, issued).transact()
        self.raiseOnZeroStatus(txid)
        token.functions.approve(self.rc0.address, approved).transact(self._txargs(sender=addr))

    def _contractFromBuildJSON(self, web3, con_name, sender=None, startgas=DEPLOY_GAS, constructor_args=None):

        if sender is None:
            sender = web3.eth.accounts[0]

        con_name_sol = con_name
        if con_name == 'RealityETH_ERC20-3.0':
            con_name_sol = 'RealityETH_ERC20_v3_0'

        build_file = '../../out/'+con_name+'.sol'+'/'+con_name_sol+'.json'

        bcode = None
        contract_if = None

        bytecode_file = '../../bytecode/' + con_name + '.bin'
        with open(bytecode_file) as f:
            bcode = f.read().strip("\n")

        with open(build_file) as f:
            fj = json.load(f)
            contract_if = fj['abi']
            bcode = fj['bytecode']['object']
            f.close()

        if bcode is None or contract_if is None:
            raise Exception("code or abi failed to load")

        if constructor_args is None:
            tx_hash = web3.eth.contract(abi=contract_if, bytecode=bcode).constructor().transact(self.deploy_tx)
        else:
            tx_hash = web3.eth.contract(abi=contract_if, bytecode=bcode).constructor(*constructor_args).transact(self.deploy_tx)

        addr = web3.eth.get_transaction_receipt(tx_hash).get('contractAddress')
        return web3.eth.contract(addr, abi=contract_if)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def testS(self):
        return

    def setUp(self):

        genesis_overrides = {'gas_limit': 9000000}
        genesis_params = PyEVMBackend._generate_genesis_params(overrides=genesis_overrides)

        l1prov = EthereumTesterProvider(EthereumTester(PyEVMBackend(genesis_params)))
        self.l1web3 = Web3(l1prov)
        self.l1web3.testing.mine()

        l2prov = EthereumTesterProvider(EthereumTester(PyEVMBackend(genesis_params)))
        self.l2web3 = Web3(l2prov)
        self.l2web3.testing.mine()

        self.deploy_tx = {
            'from': self.l2web3.eth.accounts[0],
            'gas': DEPLOY_GAS
        }

        self.standard_tx = {
            'from': self.l2web3.eth.accounts[0],
            'gas': 200000
        }


        # These users will get the l2 token
        self.L2_ALICE = self.l2web3.eth.accounts[3]
        self.L2_BOB = self.l2web3.eth.accounts[4]
        self.L2_CHARLIE = self.l2web3.eth.accounts[5]
        # Dave will just have the l2-native ETH-equivalent he's born with
        self.L2_DAVE= self.l2web3.eth.accounts[6]

        self.L1_BOB = self.L2_BOB
        self.L1_CHARLIE = self.L2_CHARLIE
        self.FORKMANAGER_INITIAL_RECIPIENT = self.l1web3.eth.accounts[7]
        self.FORKMANAGER_INITIAL_SUPPLY = 1000000000000000000

        # Make a token on L2
        k0 = self.l2web3.eth.accounts[0]

        self.l2token0 = self._contractFromBuildJSON(self.l2web3, 'ERC20Mint')
        self.l2token0.functions.mint(k0, 100000000000000).transact()

        #self.assertEqual(self.l2token0.functions.balanceOf(k0).call(), 100000000000000)
        self.assertEqual(self.l2token0.functions.balanceOf(k0).call(), 100000000000000)


        # Make a reality.eth instance on L2
        self.l2realityeth = self._contractFromBuildJSON(self.l2web3, 'RealityETH_ERC20-3.0')
        self.l2realityeth.functions.setToken(self.l2token0.address).transact()


        # Make two competing arbitrators on L2, both will be added to the whitelist nitially.

        self.arb1 = self._contractFromBuildJSON(self.l2web3, 'Arbitrator')
        self.arb2 = self._contractFromBuildJSON(self.l2web3, 'Arbitrator')
        self.arb3 = self._contractFromBuildJSON(self.l2web3, 'Arbitrator')


        # Make an AMB contract on L2, we'll pretend it's connected to L1
        self.l2AMB = self._contractFromBuildJSON(self.l2web3, 'AMB')

        self.dispute_fee = 100000000000000000


        # Make a WhitelistArbitrator. 
        # We set the reality.eth instance and dispute fee in the constructor, unlike the plain Arbitrator. TODO: should we standardize this?
        self.whitelist_arbitrator = self._contractFromBuildJSON(self.l2web3, 'WhitelistArbitrator', None, None, [self.l2realityeth.address, self.dispute_fee, self.l2AMB.address, [self.arb1.address, self.arb2.address]])
        self.assertEqual(self.whitelist_arbitrator.functions.realitio().call(), self.l2realityeth.address)
        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call())
        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb2.address).call())
        self.assertFalse(self.whitelist_arbitrator.functions.arbitrators(self.arb3.address).call())


        # Set up our competing arbitrators.
        # NB They talk to the WhitelistArbitrator contract as if it's reality.eth, so use that for setRealitio not reality.eth
        self.arb1.functions.setRealitio(self.whitelist_arbitrator.address).transact()
        self.arb1.functions.setDisputeFee(10000).transact()

        self.arb2.functions.setRealitio(self.whitelist_arbitrator.address).transact()
        self.arb2.functions.setDisputeFee(20000).transact()


        # Mint balances for our test users so and preapprove reality.eth so we don't have to keep calling approve whenever we do something.
        self.l2token0.functions.mint(self.L2_ALICE, 30000000000000).transact()
        self.l2token0.functions.mint(self.L2_BOB, 50000000000000).transact()
        self.l2token0.functions.mint(self.L2_CHARLIE, 70000000000000).transact()
        self.l2token0.functions.approve(self.l2realityeth.address, 30000000000000).transact(self._txargs(sender=self.L2_ALICE))
        self.l2token0.functions.approve(self.l2realityeth.address, 50000000000000).transact(self._txargs(sender=self.L2_BOB))
        self.l2token0.functions.approve(self.l2realityeth.address, 70000000000000).transact(self._txargs(sender=self.L2_CHARLIE))



        #self.l1token0 = self._contractFromBuildJSON(self.l1web3, 'ForkManager')
        # self.l1token0.functions.mint(k0, 800000000000000).transact()
        # self.assertEqual(self.l1token0.functions.balanceOf(k0).call(), 800000000000000)

        self.l1realityeth = self._contractFromBuildJSON(self.l1web3, 'ForkableRealityETH_ERC20', None, None)
        # self.assertEqual(self.l1realityeth.functions.token().call(), self.l1token0.address)


        libForkableRealityETH = self._contractFromBuildJSON(self.l1web3, 'ForkableRealityETH_ERC20', None, None)
        libBridgeToL2 = self._contractFromBuildJSON(self.l1web3, 'ZKBridgeToL2', None, None)
        libForkManager = self._contractFromBuildJSON(self.l1web3, 'ForkManager', None, None)
        self.bridgeToL2 = self._contractFromBuildJSON(self.l1web3, 'ZKBridgeToL2', None, None)

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        self.forkmanager = self._contractFromBuildJSON(self.l1web3, 'ForkManager', None, None)
        self.l1realityeth.functions.init(self.forkmanager.address, NULL_ADDRESS, Web3.to_bytes(hexstr=NULL_BYTES)).transact()

        # init(address payable _parentForkManager, address _realityETH, address _bridgeToL2, bool _has_governance_freeze, uint256 _parentSupply, address payable _libForkManager, address _libForkableRealityETH, address _libBridgeToL2)
        txid = self.forkmanager.functions.init(NULL_ADDRESS, self.l1realityeth.address, self.bridgeToL2.address, False, 10000, libForkManager.address, libForkableRealityETH.address, libBridgeToL2.address, self.FORKMANAGER_INITIAL_RECIPIENT, self.FORKMANAGER_INITIAL_SUPPLY).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)

        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def run_basic_cycle(self):
        self._setup_basic_cycle()

    def _setup_basic_cycle(self, question_text = "my question x"):

        ### Make a crowdfund            
        ### [Just asking the question that'll settle the crowdfund, crowdfund contract part skipped]

        question_id = calculate_question_id(self.l2realityeth.address, 0, question_text, self.whitelist_arbitrator.address, 30, 0, 0, self.L2_ALICE, 0)

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        txid = self.l2realityeth.functions.askQuestion(0, question_text, self.whitelist_arbitrator.address, 30, 0, 0).transact(self._txargs(sender=self.L2_ALICE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_ARBITRATOR], self.whitelist_arbitrator.address)

        ### Report an answer (contested)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(1), 0, 100).transact(self._txargs(sender=self.L2_BOB))
        self.raiseOnZeroStatus(txid, self.l2web3)


        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(0), 0, 200).transact(self._txargs(sender=self.L2_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(1), 0, 400).transact(self._txargs(sender=self.L2_BOB))
        self.raiseOnZeroStatus(txid, self.l2web3)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(0), 0, 2000000).transact(self._txargs(sender=self.L2_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        ### Contest an answer

        # TODO: Should the WhitelistArbitrator get paid in the native token or should it be an ERC20?
        # self.l2token0.functions.approve(self.whitelist_arbitrator.address, self.dispute_fee).transact(self._txargs(sender=self.L2_BOB))
        # self.raiseOnZeroStatus(txid)

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], False)
        self.whitelist_arbitrator.functions.requestArbitration(question_id, 3000000).transact(self._txargs(sender=self.L2_BOB, val=self.dispute_fee))
        self.raiseOnZeroStatus(txid, self.l2web3)
        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], True)

        # We can now see the question on the WhitelistArbitrator waiting for someone to answer it, it shouldn't have been picked up yet
        qa = self.whitelist_arbitrator.functions.question_arbitrations(question_id).call()
        self.assertEqual(qa[WAINDEX_ARBITRATOR], NULL_ADDRESS)

        arb1_dispute_fee = self.arb1.functions.getDisputeFee(question_id).call();
        self.assertNotEqual(arb1_dispute_fee, 0)
        txid = self.arb1.functions.requestArbitration(question_id, 0).transact(self._txargs(sender=self.L2_DAVE, val=arb1_dispute_fee));
        self.raiseOnZeroStatus(txid, self.l2web3)

        qa = self.whitelist_arbitrator.functions.question_arbitrations(question_id).call()
        self.assertEqual(qa[WAINDEX_ARBITRATOR], self.arb1.address)

        ### TODO: This should fail but doesn't seem to?
        # Now no other queued arbitrator can pick up the question.
        #arb2_dispute_fee = self.arb2.functions.getDisputeFee(question_id).call();
        #self.assertNotEqual(arb2_dispute_fee, 0)
        #with self.assertRaises(TransactionFailed):
        #    txid = self.arb2.functions.requestArbitration(question_id, 0).transact(self._txargs(sender=self.L2_DAVE, val=arb2_dispute_fee));


        # For now we'll do this as the default user, they should still own the contract
        txid = self.arb1.functions.submitAnswerByArbitrator(question_id, to_answer_for_contract(1), self.L2_DAVE).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        # We haven't called anything against the reality.eth contract yet, so it should still be pending arbitration
        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], True)

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call())
        
        # Should fail because of challenge timeout
        with self.assertRaises(TransactionFailed):
            txid = self.whitelist_arbitrator.functions.completeArbitration(question_id, to_answer_for_contract(1), self.L2_DAVE).transact()
            self.raiseOnZeroStatus(txid, self.l2web3)

        return question_id


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_uncontested_arbitration(self):
    
        question_id = self._setup_basic_cycle()

        dispute_timeout = self.whitelist_arbitrator.functions.ARB_DISPUTE_TIMEOUT().call()
        self.assertEqual(dispute_timeout, 86400);

        self._advance_clock(dispute_timeout+1)

        txid = self.whitelist_arbitrator.functions.completeArbitration(question_id, to_answer_for_contract(1), self.L2_DAVE).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], False)



    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_auction(self):

        (contest_question_id, answer_history)  = self._setup_add_arbitrator()
        last_bond = answer_history[-1]['bond']
        last_answerer = answer_history[-1]['answerer']
        last_answer = answer_history[-1]['answer']
        previous_history_hash = answer_history[-1]['previous_history_hash']

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        history_hash = contestq[QINDEX_HISTORY_HASH]

        add_amount = last_bond

        bob_extra_bal = 7654
        charlie_extra_bal = 938493

        # To be able to fork an arbitrator we need to post at least 1% of supply
        fork_amount = int(self.FORKMANAGER_INITIAL_SUPPLY * 5 / 100)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, 0, "bob starts off with 0")
        charlie_bal = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal, 0, "charlie starts off with 0")


        # Give everyone some ForkManager coins so we can test what happens when they pick sides etc later
        # Bob also needs enough to pay for the forking
        txid = self.forkmanager.functions.transfer(self.L1_BOB, fork_amount+bob_extra_bal).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, charlie_extra_bal).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, fork_amount).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        self.assertTrue(self.forkmanager.functions.isUnForked().call())

        txid = self.forkmanager.functions.requestArbitrationByFork(contest_question_id, 0).transact(self._txargs(sender=self.L1_BOB, gas=3000000))
        self.raiseOnZeroStatus(txid, self.l1web3)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, bob_extra_bal, "after requesting the fork, bob no longer has the fork amount but still has his extra balance")
    
        # time to bid


        self._advance_clock(604800, self.l1web3)


        # TODO: First to_answer_for_contract should be previous history hash
        txid = self.forkmanager.functions.deployFork(True, previous_history_hash, last_answer, last_answerer, last_bond).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)

        # deployFork will create a LogNewAnswer event. 
        # We'll need this for the claim transaction.
        ans_log = self.l1realityeth.events.LogNewAnswer().process_receipt(rcpt)

        # print(rcpt)
        self.raiseOnZeroStatus(txid, self.l1web3)

        ts1 = self._block_timestamp(self.l1web3)
        txid = self.forkmanager.functions.deployFork(False, previous_history_hash, last_answer, last_answerer, last_bond).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)
        # print(rcpt)
        self.raiseOnZeroStatus(txid, self.l1web3)


        child_fm1_addr = self.forkmanager.functions.childForkManager1().call()
        child_fm2_addr = self.forkmanager.functions.childForkManager2().call()

        child_fm1 = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        child_fm2 = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        





    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_contested_token_migration(self):
        self._setup_contested_arbitration_with_fork()
        self.assertTrue(self.forkmanager.functions.isForkingResolved())

        bob_bal_parent = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_parent, 54000)

        self.forkmanager.functions.migrateToChildren(4000, False, False).transact(self._txargs(sender=self.L1_BOB))

        bob_bal_parent = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_parent, 50000)

        child_fm1_addr = self.forkmanager.functions.childForkManager1().call()
        child_fm2_addr = self.forkmanager.functions.childForkManager2().call()

        child_fm1 = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        child_fm2 = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        
        bob_bal_fm1 = child_fm1.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_fm1, 4000)

        bob_bal_fm2 = child_fm1.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_fm2, 4000)

        self.forkmanager.functions.migrateToChildren(1000, False, True).transact(self._txargs(sender=self.L1_BOB))
        self.assertEqual(child_fm1.functions.balanceOf(self.L1_BOB).call(), 5000)
        self.assertEqual(child_fm2.functions.balanceOf(self.L1_BOB).call(), 4000)

        self.forkmanager.functions.migrateToChildren(500, True, False).transact(self._txargs(sender=self.L1_BOB))
        self.assertEqual(child_fm1.functions.balanceOf(self.L1_BOB).call(), 5000)
        self.assertEqual(child_fm2.functions.balanceOf(self.L1_BOB).call(), 4500)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_setup_simple(self):

        pass


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_contested_arbitration(self):
        self._setup_contested_arbitration_with_fork()

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_clear_questions_after_arbitrator_removed(self):
        q2id = self._setup_clear_questions_after_arbitrator_removed()

        handle_timeout = self.whitelist_arbitrator.functions.QUESTION_UNHANDLED_TIMEOUT().call()

        # Should fail if the timeout is not yet passed
        with self.assertRaises(TransactionFailed):
            txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(q2id).transact(self._txargs())
            self.raiseOnZeroStatus(txid, self.l2web3)

        self._advance_clock(handle_timeout+1)

        # Should succeed now
        txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(q2id).transact(self._txargs())
        self.raiseOnZeroStatus(txid, self.l2web3)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_reassign_question_after_arbitrator_removed(self):
        q2id = self._setup_clear_questions_after_arbitrator_removed()

        # Now we should be able to either answer with a different arbitrator, or wait for the timeout and cancel the arbitration request.
        #txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(q2id).transact(self._txargs())
        #self.raiseOnZeroStatus(txid, self.l2web3)

        # arb1 should be gone but arb2 should still be there so they can take the question
        self.assertFalse(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call())
        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb2.address).call())

        # TODO: Check what the flow is for taking a job and make sure we're testing it correctly
        # arb0 cannot accept jobs any more
        # arb2 can accept this job

        fee = self.arb2.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()
        txid = self.arb2.functions.requestArbitration(q2id, 0).transact(self._txargs(val=fee))
        self.raiseOnZeroStatus(txid, self.l2web3)


    def _setup_clear_questions_after_arbitrator_removed(self):
        # Add an extra question and bring it up to arbitration
        q2id = self._setup_basic_cycle("my question y")

        is_pending_arb = self.l2realityeth.functions.isPendingArbitration(q2id).call()
        self.assertTrue(is_pending_arb)

        # arbitrator should now have accepted the task, but not yet completed it
        qa_rec = self.whitelist_arbitrator.functions.question_arbitrations(q2id).call()
        qa_bounty = qa_rec[2]
        self.assertGreater(qa_bounty, 0)

        # Should fail as it's being handled
        with self.assertRaises(TransactionFailed):
            txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(q2id).transact(self._txargs())
            self.raiseOnZeroStatus(txid, self.l2web3)

        # Should fail as the arbitrator is still listed
        with self.assertRaises(TransactionFailed):
            txid = self.whitelist_arbitrator.functions.clearRequestFromRemovedArbitrator(q2id).transact(self._txargs())
            self.raiseOnZeroStatus(txid, self.l2web3)

        # Now remove the arbitrator over a different question without a fork
        (question_id, contest_question_id, freeze_amount, last_bond, last_history_hash, last_answer, last_answerer, answer_history, new_history_hash) = self._setup_contested_arbitration()

        # Let the thing timeout so we can remove the arbitrator without a challenge
        reality_eth_timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(reality_eth_timeout, 604800);

        contest_q = self.l1realityeth.functions.questions(contest_question_id).call()
        best_answer = self.l1realityeth.functions.getBestAnswer(contest_question_id).call()
        self.assertEqual(from_answer_for_contract(best_answer), 1)

        arb_pending = self.l1realityeth.functions.isPendingArbitration(contest_question_id).call()
        self.assertFalse(arb_pending)

        timeout = self.l1realityeth.functions.getTimeout(contest_question_id).call()
        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(timeout+1, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertNotEqual(ts1, ts2)

        finalize_ts = self.l1realityeth.functions.getFinalizeTS(contest_question_id).call()
        self.assertLess(ts1, finalize_ts)
        self.assertGreater(ts2, finalize_ts)

        # The ForkableRealityETH_ERC20 needs you to call finalize, unlike the normal one which finalizes automatically based on time
        self.l1realityeth.functions.finalize(contest_question_id).transact()

        is_finalized = self.l1realityeth.functions.isFinalized(contest_question_id).call()
        self.assertTrue(is_finalized)

        txid = self.forkmanager.functions.executeRemoveArbitratorFromWhitelist(contest_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        bridge_log = self.bridgeToL2.events.LogPassMessage().process_receipt(tx_receipt)
        self.assertEqual(len(bridge_log), 1, "The bridge on L1 was called and logged an event")
        call_data = bridge_log[0]['args']['_data']

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "starts off on list")
        self.assertTrue(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "starts off frozen")

        # The executeRemoveArbitratorFromWhitelist call should have called the bridge with the code:
        # bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        # bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        # We'll imitate this by calling our dummy bridge ourselves
        txid = self.l2AMB.functions.passMessage(
            FORKMANAGER_SPECIAL_ADDRESS,  #Rewritten from self.forkmanager.address
            self.whitelist_arbitrator.address,
            call_data,
            5000000,
            Web3.to_bytes(hexstr=NULL_BYTES),
            Web3.to_bytes(hexstr=NULL_BYTES)
        ).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertFalse(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "no longer on list")

        # Now we should be able to call clearRequestFromRemovedArbitrator to clear the original question
        txid = self.whitelist_arbitrator.functions.clearRequestFromRemovedArbitrator(q2id).transact(self._txargs())
        self.raiseOnZeroStatus(txid, self.l2web3)


        return q2id





    

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_clear_unhandled_arbitration(self):

        question_id = calculate_question_id(self.l2realityeth.address, 0, "my question x", self.whitelist_arbitrator.address, 30, 0, 0, self.L2_ALICE, 0)

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        txid = self.l2realityeth.functions.askQuestion(0, "my question x", self.whitelist_arbitrator.address, 30, 0, 0).transact(self._txargs(sender=self.L2_ALICE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_ARBITRATOR], self.whitelist_arbitrator.address)

        ### Report an answer (contested)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(1), 0, 100).transact(self._txargs(sender=self.L2_BOB))
        self.raiseOnZeroStatus(txid, self.l2web3)


        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(0), 0, 200).transact(self._txargs(sender=self.L2_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(1), 0, 400).transact(self._txargs(sender=self.L2_BOB))
        self.raiseOnZeroStatus(txid, self.l2web3)

        txid = self.l2realityeth.functions.submitAnswerERC20(question_id, to_answer_for_contract(0), 0, 2000000).transact(self._txargs(sender=self.L2_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l2web3)

        bob_bal_before_request = self.l2web3.eth.get_balance(self.L2_BOB)
        # self.whitelist_arbitrator.functions.balanceOf(self.L1_BOB).call()

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], False)
        txid = self.whitelist_arbitrator.functions.requestArbitration(question_id, 3000000).transact(self._txargs(sender=self.L2_BOB, val=self.dispute_fee))
        self.raiseOnZeroStatus(txid, self.l2web3)
        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], True)

        request_arb_gas = 127470

        bob_bal_after_request = self.l2web3.eth.get_balance(self.L2_BOB)
        #self.assertEqual(bob_bal_before_request - bob_bal_after_request , self.dispute_fee + request_arb_gas)

        # We can now see the question on the WhitelistArbitrator waiting for someone to answer it, it shouldn't have been picked up yet
        qa = self.whitelist_arbitrator.functions.question_arbitrations(question_id).call()
        self.assertEqual(qa[WAINDEX_ARBITRATOR], NULL_ADDRESS)

        handle_timeout = self.whitelist_arbitrator.functions.QUESTION_UNHANDLED_TIMEOUT().call()
        self.assertEqual(handle_timeout, 86400);

        # Bob should have no balance in the arbitrator contract
        bob_bal_in_contract = self.whitelist_arbitrator.functions.balanceOf(self.L2_BOB).call()
        self.assertEqual(bob_bal_in_contract, 0)

        # The whitelist arbitrator should list Bob as the payer, and the amount he paid as the bounty
        #balanceOf[question_arbitrations[question_id].payer] = balanceOf[question_arbitrations[question_id].payer] + question_arbitrations[question_id].bounty;
        arb_rec = self.whitelist_arbitrator.functions.question_arbitrations(question_id).call()
        #address arbitrator;
        #address payer;
        #uint256 bounty;
        #bytes32 msg_hash;
        #uint256 finalize_ts;
        #uint256 last_action_ts;

        # no arbitrator yet
        self.assertEqual(arb_rec[0], NULL_ADDRESS)
        self.assertEqual(arb_rec[1], self.L2_BOB)
        self.assertEqual(arb_rec[2], self.dispute_fee)

        # Should fail if the timeout is not yet passed
        with self.assertRaises(TransactionFailed):
            txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(question_id).transact(self._txargs())
            self.raiseOnZeroStatus(txid, self.l2web3)

        self._advance_clock(handle_timeout+1)

        # Should succeed now
        txid = self.whitelist_arbitrator.functions.cancelUnhandledArbitrationRequest(question_id).transact(self._txargs())
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertEqual(self.l2realityeth.functions.questions(question_id).call()[QINDEX_IS_PENDING_ARBITRATION], False)

        arb_rec2 = self.whitelist_arbitrator.functions.question_arbitrations(question_id).call()
        self.assertEqual(arb_rec2[0], NULL_ADDRESS)
        self.assertEqual(arb_rec2[1], NULL_ADDRESS)
        self.assertEqual(arb_rec2[2], 0)

        # Bob should now have his dispute fee back in the contract
        bob_bal_in_contract2 = self.whitelist_arbitrator.functions.balanceOf(self.L2_BOB).call()
        self.assertEqual(bob_bal_in_contract2, self.dispute_fee)

        bob_bal_before_withdraw = self.l2web3.eth.get_balance(self.L2_BOB)

        txid = self.whitelist_arbitrator.functions.withdraw().transact(self._txargs(sender=self.L2_BOB, gas=40000))
        self.raiseOnZeroStatus(txid, self.l2web3)

        tx_receipt = self.l2web3.eth.get_transaction_receipt(txid)
        gas_used = tx_receipt['cumulativeGasUsed']
        gas_price = tx_receipt['effectiveGasPrice']
        spent_on_gas = gas_price * gas_used
        self.assertGreater(self.dispute_fee, spent_on_gas)
        withdraw_log = self.whitelist_arbitrator.events.LogWithdraw().process_receipt(tx_receipt)
        self.assertEqual(len(withdraw_log), 1, "The whitelist arbitrator on L2 was called and logged an event")
        self.assertEqual(withdraw_log[0]['args']['user'], self.L2_BOB)
        self.assertEqual(withdraw_log[0]['args']['amount'], self.dispute_fee)

        bob_bal_in_contract3 = self.whitelist_arbitrator.functions.balanceOf(self.L2_BOB).call()
        self.assertEqual(bob_bal_in_contract3, 0)

        bob_bal_after_withdraw = self.l2web3.eth.get_balance(self.L2_BOB)
        self.assertGreater(bob_bal_after_withdraw, bob_bal_before_withdraw)

        bal_change = bob_bal_after_withdraw - bob_bal_before_withdraw

        self.assertGreater(self.dispute_fee, bal_change)
        self.assertEqual(bal_change, self.dispute_fee - spent_on_gas)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_post_fork_arbitrator_removal(self):
        
        (contest_question_id, answer_history1, answer_history2, child_fm1, child_fm2) = self._setup_contested_arbitration_with_fork()
        txid = child_fm1.functions.executeRemoveArbitratorFromWhitelist(contest_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        bridge_log = self.bridgeToL2.events.LogPassMessage().process_receipt(tx_receipt)
        self.assertEqual(len(bridge_log), 1, "The bridge on L1 was called and logged an event")
        call_data = bridge_log[0]['args']['_data']

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "starts off on list")
        self.assertTrue(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "starts off frozen")

        # The executeRemoveArbitratorFromWhitelist call should have called the bridge with the code:
        # bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        # bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        # We'll imitate this by calling our dummy bridge ourselves
        txid = self.l2AMB.functions.passMessage(
            FORKMANAGER_SPECIAL_ADDRESS,  #Rewritten from self.forkmanager.address
            self.whitelist_arbitrator.address,
            call_data,
            5000000,
            Web3.to_bytes(hexstr=NULL_BYTES),
            Web3.to_bytes(hexstr=NULL_BYTES)
        ).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertFalse(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "ends up not on list")
        self.assertFalse(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "ends up not frozen")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_uncontested_arbitrator_removal(self):
        
        (contest_question_id, answer_history1, answer_history2, child_fm1, child_fm2) = self._setup_contested_arbitration_with_fork()
        txid = child_fm1.functions.executeRemoveArbitratorFromWhitelist(contest_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        bridge_log = self.bridgeToL2.events.LogPassMessage().process_receipt(tx_receipt)
        self.assertEqual(len(bridge_log), 1, "The bridge on L1 was called and logged an event")
        call_data = bridge_log[0]['args']['_data']

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "starts off on list")
        self.assertTrue(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "starts off frozen")

        # The executeRemoveArbitratorFromWhitelist call should have called the bridge with the code:
        # bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        # bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        # We'll imitate this by calling our dummy bridge ourselves
        txid = self.l2AMB.functions.passMessage(
            FORKMANAGER_SPECIAL_ADDRESS,  #Rewritten from self.forkmanager.address
            self.whitelist_arbitrator.address,
            call_data,
            5000000,
            Web3.to_bytes(hexstr=NULL_BYTES),
            Web3.to_bytes(hexstr=NULL_BYTES)
        ).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertFalse(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "ends up not on list")
        self.assertFalse(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "ends up not frozen")






    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_post_fork_arbitrator_unfreezing(self):
        
        (contest_question_id, answer_history1, answer_history2, child_fm1, child_fm2) = self._setup_contested_arbitration_with_fork()
        txid = child_fm2.functions.executeUnfreezeArbitratorOnWhitelist(contest_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        bridge_log = self.bridgeToL2.events.LogPassMessage().process_receipt(tx_receipt)
        self.assertEqual(len(bridge_log), 1, "The bridge on L1 was called and logged an event")
        call_data = bridge_log[0]['args']['_data']

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "starts off on list")
        self.assertTrue(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "starts off frozen")

        # The executeRemoveArbitratorFromWhitelist call should have called the bridge with the code:
        # bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(whitelist_arbitrator).removeArbitrator.selector, arbitrator_to_remove);
        # bridgeToL2.requireToPassMessage(whitelist_arbitrator, data, 0);
        # We'll imitate this by calling our dummy bridge ourselves
        txid = self.l2AMB.functions.passMessage(
            FORKMANAGER_SPECIAL_ADDRESS,  #Rewritten from self.forkmanager.address
            self.whitelist_arbitrator.address,
            call_data,
            5000000,
            Web3.to_bytes(hexstr=NULL_BYTES),
            Web3.to_bytes(hexstr=NULL_BYTES)
        ).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        self.assertTrue(self.whitelist_arbitrator.functions.arbitrators(self.arb1.address).call(), "ends up still on list")
        self.assertFalse(self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call(), "ends up not frozen")

        # TODO: Test using the arbitrator which is now unfrozen


    # TODO: Test the process of claiming from reality.eth on each branch

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_setup_add_arbitrator(self):
        self._setup_add_arbitrator() 

    def _setup_add_arbitrator(self):

        answer_history = []

        txid = self.forkmanager.functions.beginAddArbitratorToWhitelist(self.whitelist_arbitrator.address, self.arb3.address).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)
        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)

        ask_log = self.l1realityeth.events.LogNewQuestion().process_receipt(tx_receipt)
        contest_question_id = ask_log[0]['args']['question_id']

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, 12345).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, 12345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        last_history_hash = contestq[QINDEX_HISTORY_HASH]

        txid = self.l1realityeth.functions.submitAnswerERC20(contest_question_id, to_answer_for_contract(1), 0, 12345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        ans_log = self.l1realityeth.events.LogNewAnswer().process_receipt(tx_receipt)

        answer_history.append(self._log_to_answer_history(ans_log, last_history_hash))

        return (contest_question_id, answer_history)

    def _log_to_answer_history(self, ans_log, last_history_hash):

        last_bond = ans_log[0]['args']['bond']
        last_answerer = ans_log[0]['args']['user']
        last_answer = ans_log[0]['args']['answer']

        return {
            'bond': last_bond,
            'answerer': last_answerer,
            'answer': last_answer,
            'previous_history_hash': last_history_hash,
        }


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_contested_add_arbitrator(self):

        (contest_question_id, answer_history)  = self._setup_add_arbitrator()
        last_bond = answer_history[-1]['bond']
        last_answerer = answer_history[-1]['answerer']
        last_answer = answer_history[-1]['answer']
        previous_history_hash = answer_history[-1]['previous_history_hash']

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        history_hash = contestq[QINDEX_HISTORY_HASH]

        add_amount = last_bond

        bob_extra_bal = 7654
        charlie_extra_bal = 938493

        # To be able to fork an arbitrator we need to post at least 1% of supply
        fork_amount = int(self.FORKMANAGER_INITIAL_SUPPLY * 5 / 100)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, 0, "bob starts off with 0")
        charlie_bal = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal, 0, "charlie starts off with 0")


        # Give everyone some ForkManager coins so we can test what happens when they pick sides etc later
        # Bob also needs enough to pay for the forking
        txid = self.forkmanager.functions.transfer(self.L1_BOB, fork_amount+bob_extra_bal).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, charlie_extra_bal).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, fork_amount).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        self.assertTrue(self.forkmanager.functions.isUnForked().call())

        txid = self.forkmanager.functions.requestArbitrationByFork(contest_question_id, 0).transact(self._txargs(sender=self.L1_BOB, gas=3000000))
        self.raiseOnZeroStatus(txid, self.l1web3)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, bob_extra_bal, "after requesting the fork, bob no longer has the fork amount but still has his extra balance")

        self.assertEqual(self.l1realityeth.functions.questions(contest_question_id).call()[QINDEX_IS_PENDING_ARBITRATION], True)
        self.assertFalse(self.forkmanager.functions.isUnForked().call())

        ##txid = self.l1realityeth.functions.submitAnswerERC20(contest_question_id, to_answer_for_contract(1), 0, 12345).transact(self._txargs(sender=self.L1_CHARLIE))


        self._advance_clock(604800, self.l1web3)


        # TODO: First to_answer_for_contract should be previous history hash
        txid = self.forkmanager.functions.deployFork(True, previous_history_hash, last_answer, last_answerer, last_bond).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)

        # deployFork will create a LogNewAnswer event. 
        # We'll need this for the claim transaction.
        ans_log = self.l1realityeth.events.LogNewAnswer().process_receipt(rcpt)

        # print(rcpt)
        self.raiseOnZeroStatus(txid, self.l1web3)

        ts1 = self._block_timestamp(self.l1web3)
        txid = self.forkmanager.functions.deployFork(False, previous_history_hash, last_answer, last_answerer, last_bond).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)
        # print(rcpt)
        self.raiseOnZeroStatus(txid, self.l1web3)


        child_fm1_addr = self.forkmanager.functions.childForkManager1().call()
        child_fm2_addr = self.forkmanager.functions.childForkManager2().call()

        child_fm1 = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        child_fm2 = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        
        self._advance_clock(60, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertNotEqual(ts1, ts2)

        # print(self.forkmanager.abi)
        realityeth1_addr = child_fm1.functions.realityETH().call()
        realityeth1 = self.l1web3.eth.contract(realityeth1_addr, abi=self.l1realityeth.abi)

        realityeth2_addr = child_fm2.functions.realityETH().call()
        realityeth2 = self.l1web3.eth.contract(realityeth2_addr, abi=self.l1realityeth.abi)

        q1 = realityeth1.functions.questions(contest_question_id).call()

        finalization_ts = q1[QINDEX_FINALIZATION_TS]
        self.assertTrue(ts2 > finalization_ts, "finalization timestamp has passed")
        is_finalized = realityeth1.functions.isFinalized(contest_question_id).call()
        self.assertTrue(is_finalized, "q1 finalized")

        q2 = realityeth2.functions.questions(contest_question_id).call()
        result1 = realityeth1.functions.resultFor(contest_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(1))
        result2 = realityeth2.functions.resultFor(contest_question_id).call()
        self.assertEqual(result2, to_answer_for_contract(0))

        bal1 = child_fm1.functions.balanceOf(realityeth1_addr).call()
        # Each reality.eth instance should have enough tokens
        self.assertEqual(bal1, add_amount)

        bal2 = child_fm2.functions.balanceOf(realityeth2_addr).call()
        # Each reality.eth instance should have enough tokens
        self.assertEqual(bal1, add_amount)

        # TODO: Test the claiming process

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, bob_extra_bal)
        charlie_bal = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal, charlie_extra_bal)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, 7654)
        charlie_bal = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal, 938493)

        return

        txid = self.forkmanager.functions.bid(40, 321).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)
        bob_bal_parent = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_parent, 7333)

        txid = self.forkmanager.functions.bid(20, 345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)
        charlie_bal_parent = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal_parent, 938148)

        txid = self.forkmanager.functions.resolveFork().transact(self._txargs(gas=3000000))
        self.raiseOnZeroStatus(txid, self.l1web3)

        replaced_by_addr = self.forkmanager.functions.replacedByForkManager().call()
        self.assertEqual(child_fm2_addr, replaced_by_addr)
        
        replaced_by_fm = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        self.assertTrue(replaced_by_fm.functions.isWinner().call())
        self.assertFalse(replaced_by_fm.functions.isLoser().call())

        not_replaced_by = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        self.assertFalse(not_replaced_by.functions.isWinner().call())
        self.assertTrue(not_replaced_by.functions.isLoser().call())
        
        return (contest_question_id, child_fm1, child_fm2)


    def _setup_contested_arbitration(self):

        question_id = self._setup_basic_cycle()

        answer_history = []

        # question = self.whitelist_arbitrator.address + QUESTION_DELIM + self.arb1.address

        txid = self.forkmanager.functions.beginRemoveArbitratorFromWhitelist(self.whitelist_arbitrator.address, self.arb1.address).transact()
        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        ask_log = self.l1realityeth.events.LogNewQuestion().process_receipt(tx_receipt)
        contest_question_id = ask_log[0]['args']['question_id']

        # To be able to freeze an arbitrator we need to post at least 1% of supply
        freeze_amount = int(self.FORKMANAGER_INITIAL_SUPPLY * 1 / 100)

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, freeze_amount+12345).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, freeze_amount).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        last_history_hash = contestq[QINDEX_HISTORY_HASH]

        txid = self.l1realityeth.functions.submitAnswerERC20(contest_question_id, to_answer_for_contract(1), 0, freeze_amount).transact(self._txargs(sender=self.L1_CHARLIE))
        #self.raiseOnZeroStatus(txid, self.l1web3)
        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        answer_log = self.l1realityeth.events.LogNewAnswer().process_receipt(tx_receipt)

        history_item = self._log_to_answer_history(answer_log, last_history_hash)
        last_bond = history_item['bond']
        last_answer = history_item['answer']
        last_answerer = history_item['answerer']

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        new_history_hash = contestq[QINDEX_HISTORY_HASH]

        answer_history.append(history_item)

        self.assertEqual(answer_history[-1]['bond'], freeze_amount, "expected last bond")
        self.assertEqual(answer_history[-1]['answer'], to_answer_for_contract(1), "epected last answer")
        self.assertEqual(answer_history[-1]['answerer'], self.L1_CHARLIE, "epected last answerer")

        #contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        #print("hh after submit" + encode_hex(contestq[QINDEX_HISTORY_HASH]))

        txid = self.forkmanager.functions.freezeArbitratorOnWhitelist(contest_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        #contestq = self.l1realityeth.functions.questions(contest_question_id).call()
        #print("hh after freeze (should be same as submit)")
        #print(encode_hex(contestq[QINDEX_HISTORY_HASH]))

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        bridge_log = self.bridgeToL2.events.LogPassMessage().process_receipt(tx_receipt)
        call_data = bridge_log[0]['args']['_data']



        is_frozen = self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call()
        self.assertFalse(is_frozen, "not frozen at start")

        # The freezeArbitratorOnWhitelist call should have called the bridge with the code:
        # bytes memory data = abi.encodeWithSelector(WhitelistArbitrator(arbitrator_to_remove).freezeArbitrator.selector, arbitrator_to_remove);
        # We'll imitate this by calling our dummy bridge ourselves
        bridge_call_data = self.whitelist_arbitrator.encodeABI(fn_name="freezeArbitrator", args=[self.arb1.address])
        txid = self.l2AMB.functions.passMessage(
            FORKMANAGER_SPECIAL_ADDRESS,  #Rewritten from self.forkmanager.address
            self.whitelist_arbitrator.address,
            call_data,
            5000000,
            Web3.to_bytes(hexstr=NULL_BYTES),
            Web3.to_bytes(hexstr=NULL_BYTES)
        ).transact()
        self.raiseOnZeroStatus(txid, self.l2web3)

        is_frozen = self.whitelist_arbitrator.functions.frozen_arbitrators(self.arb1.address).call()
        self.assertTrue(is_frozen, "frozen at end")

        return (question_id, contest_question_id, freeze_amount, last_bond, last_history_hash, last_answer, last_answerer, answer_history, new_history_hash)

    def _setup_contested_arbitration_with_fork(self):

        (question_id, contest_question_id, freeze_amount, last_bond, last_history_hash, last_answer, last_answerer, answer_history, new_history_hash) = self._setup_contested_arbitration()
        
        # TODO: Break this out into different functions and handle some of the other scenarios

        # Bob to contest on L1

        # To be able to fork an arbitrator we need to post at least 1% of supply
        fork_amount = int(self.FORKMANAGER_INITIAL_SUPPLY * 5 / 100)

        txid = self.forkmanager.functions.transfer(self.L1_BOB, fork_amount+54321).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, fork_amount).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        contestq = self.l1realityeth.functions.questions(contest_question_id).call()

        self.assertTrue(self.forkmanager.functions.isUnForked().call())

        expected_hh = self.l1realityeth.functions.getHistoryHash(contest_question_id).call()
        calculated_hh = calculate_history_hash(to_answer_for_contract(0), to_answer_for_contract(1), freeze_amount, self.L1_CHARLIE, False)
        self.assertEqual(expected_hh, calculated_hh)

        txid = self.forkmanager.functions.requestArbitrationByFork(contest_question_id, 0).transact(self._txargs(gas=3000000, sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        expected_hh2 = self.l1realityeth.functions.getHistoryHash(contest_question_id).call()
        self.assertEqual(expected_hh, expected_hh2, "arbitration should not change the history hash")


        self.assertEqual(self.l1realityeth.functions.questions(contest_question_id).call()[QINDEX_IS_PENDING_ARBITRATION], True)
        self.assertFalse(self.forkmanager.functions.isUnForked().call())

        self.assertEqual(self.l1realityeth.functions.getBond(contest_question_id).call(),self.l1realityeth.functions.getCumulativeBonds(contest_question_id).call(), "Cumulative bond should equal last bond as there was only one answer")
        self.assertEqual(last_bond, self.l1realityeth.functions.getBond(contest_question_id).call(), "last bond is what we expect")


        # Recreate the history hash and test it ourselves
        expected_hh = self.l1realityeth.functions.getHistoryHash(contest_question_id).call()
        calculated_hh = calculate_history_hash(last_history_hash, last_answer, last_bond, last_answerer, False)
        self.assertEqual(expected_hh, calculated_hh)


        self.assertEqual(len(answer_history), 1, "answer_history should still only have 1 entry")

        # From now on each reality.eth instance will have a different history as the arbitrator will settle them differently
        answer_history1 = answer_history[:]
        answer_history2 = answer_history[:]




        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"
        # The forkmanager should have deployed an auction contract
        auction = self.forkmanager.functions.auction().call()
        self.assertNotEqual(auction, NULL_ADDRESS)

        bob_bal = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal, 54321)
        charlie_bal = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal, 12345)

        txid = self.forkmanager.functions.bid(40, 321).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        bob_bal_parent = self.forkmanager.functions.balanceOf(self.L1_BOB).call()
        self.assertEqual(bob_bal_parent, 54000)

        txid = self.forkmanager.functions.bid(20, 345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)
        charlie_bal_parent = self.forkmanager.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_bal_parent, 12000)






        self._advance_clock(604800, self.l1web3)


        # First to_answer_for_contract should be previous history hash
        # function deployFork(bool yes_or_no, bytes32 last_history_hash, bytes32 last_answer, address last_answerer, uint256 last_bond)
        # txid = self.l1realityeth.functions.submitAnswerERC20(contest_question_id, to_answer_for_contract(1), 0, freeze_amount).transact(self._txargs(sender=self.L1_CHARLIE))
        txid = self.forkmanager.functions.deployFork(True, answer_history[-1]['previous_history_hash'], answer_history[-1]['answer'], answer_history[-1]['answerer'], answer_history[-1]['bond']).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)
        self.raiseOnZeroStatus(txid, self.l1web3)

        answer_log1 = self.l1realityeth.events.LogNewAnswer().process_receipt(rcpt)
        history_item1 = self._log_to_answer_history(answer_log1, new_history_hash)
        answer_history1.append(history_item1)

        #TRY: Let this time out instead of challenging it, and see if we can claim it

        ts1 = self._block_timestamp(self.l1web3)
        txid = self.forkmanager.functions.deployFork(False, answer_history[-1]['previous_history_hash'], answer_history[-1]['answer'], answer_history[-1]['answerer'], answer_history[-1]['bond']).transact(self._txargs(gas=6000000))
        rcpt = self.l1web3.eth.get_transaction_receipt(txid)
        # print(rcpt)
        self.raiseOnZeroStatus(txid, self.l1web3)

        answer_log2 = self.l1realityeth.events.LogNewAnswer().process_receipt(rcpt)
        history_item2 = self._log_to_answer_history(answer_log2, new_history_hash)
        answer_history2.append(history_item2)

        self.assertNotEqual(answer_history1[-1]['answerer'], answer_history2[-1]['answerer'], "Different forks should have different answerers")
        self.assertNotEqual(answer_history1[-1]['answer'], answer_history2[-1]['answer'], "Different forks should have different answers")
        self.assertEqual(answer_history1[-1]['previous_history_hash'], answer_history2[-1]['previous_history_hash'], "Different forks should the same previous history hashes")
        self.assertEqual(answer_history1[-1]['bond'], answer_history2[-1]['bond'], "Different forks should the same bonds")
        self.assertEqual(answer_history1[-1]['bond'], 0, "final answer history bonds should be 0 as they are from arbitration")

        self.assertEqual(len(answer_history), 1, "answer_history should still only have 1 entry")
        self.assertEqual(len(answer_history1), len(answer_history)+1, "answer_history 1 should have 1 more entry")
        self.assertEqual(len(answer_history2), len(answer_history)+1, "answer_history 2 should have 1 more entry")

        child_fm1_addr = self.forkmanager.functions.childForkManager1().call()
        child_fm2_addr = self.forkmanager.functions.childForkManager2().call()

        child_fm1 = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        child_fm2 = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        
        self._advance_clock(60, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertNotEqual(ts1, ts2)


        # print(self.forkmanager.abi)
        realityeth1_addr = child_fm1.functions.realityETH().call()
        realityeth1 = self.l1web3.eth.contract(realityeth1_addr, abi=self.l1realityeth.abi)

        realityeth2_addr = child_fm2.functions.realityETH().call()
        realityeth2 = self.l1web3.eth.contract(realityeth2_addr, abi=self.l1realityeth.abi)

        q1 = realityeth1.functions.questions(contest_question_id).call()

        finalization_ts = q1[QINDEX_FINALIZATION_TS]
        self.assertTrue(ts2 > finalization_ts, "finalization timestamp has passed")
        is_finalized = realityeth1.functions.isFinalized(contest_question_id).call()
        self.assertTrue(is_finalized, "q1 finalized")

        q2 = realityeth2.functions.questions(contest_question_id).call()
        result1 = realityeth1.functions.resultFor(contest_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(1))
        result2 = realityeth2.functions.resultFor(contest_question_id).call()
        self.assertEqual(result2, to_answer_for_contract(0))

        bal1 = child_fm1.functions.balanceOf(realityeth1_addr).call()
        # Each reality.eth instance should have enough tokens
        self.assertEqual(bal1, freeze_amount)

        bal2 = child_fm2.functions.balanceOf(realityeth2_addr).call()
        # Each reality.eth instance should have enough tokens
        self.assertEqual(bal1, freeze_amount)

        txid = self.forkmanager.functions.resolveFork().transact(self._txargs(gas=3000000))
        self.raiseOnZeroStatus(txid, self.l1web3)

        replaced_by_addr = self.forkmanager.functions.replacedByForkManager().call()
        self.assertEqual(child_fm2_addr, replaced_by_addr)
        
        replaced_by_fm = self.l1web3.eth.contract(child_fm2_addr, abi=self.forkmanager.abi)
        self.assertTrue(replaced_by_fm.functions.isWinner().call())
        self.assertFalse(replaced_by_fm.functions.isLoser().call())

        not_replaced_by = self.l1web3.eth.contract(child_fm1_addr, abi=self.forkmanager.abi)
        self.assertFalse(not_replaced_by.functions.isWinner().call())
        self.assertTrue(not_replaced_by.functions.isLoser().call())


        fm1_bridge = child_fm1.functions.bridgeToL2().call()
        fm2_bridge = child_fm2.functions.bridgeToL2().call()
        self.assertNotEqual(fm1_bridge, fm2_bridge, "The forkmanagers should have their own separate bridges")

        return (contest_question_id, answer_history1, answer_history2, child_fm1, child_fm2)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_post_fork_claims(self):

        (contest_question_id, answer_history1, answer_history2, child_fm1, child_fm2) = self._setup_contested_arbitration_with_fork()

        # print(self.forkmanager.abi)
        realityeth1_addr = child_fm1.functions.realityETH().call()
        realityeth1 = self.l1web3.eth.contract(realityeth1_addr, abi=self.l1realityeth.abi)

        realityeth2_addr = child_fm2.functions.realityETH().call()
        realityeth2 = self.l1web3.eth.contract(realityeth2_addr, abi=self.l1realityeth.abi)

        q1 = realityeth1.functions.questions(contest_question_id).call()

        finalization_ts = q1[QINDEX_FINALIZATION_TS]

        self._advance_clock(604800, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)

        self.assertTrue(ts2 > finalization_ts, "finalization timestamp has passed")
        is_finalized = realityeth1.functions.isFinalized(contest_question_id).call()
        self.assertTrue(is_finalized, "q1 finalized")

        q2 = realityeth2.functions.questions(contest_question_id).call()
        result1 = realityeth1.functions.resultFor(contest_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(1))
        result2 = realityeth2.functions.resultFor(contest_question_id).call()
        self.assertEqual(result2, to_answer_for_contract(0))

        bal1 = child_fm1.functions.balanceOf(realityeth1_addr).call()
        # Each reality.eth instance should have enough tokens
        bal2 = child_fm2.functions.balanceOf(realityeth2_addr).call()
        # Each reality.eth instance should have enough tokens

        #self.assertTrue(False, "TODO: Implement the claim tests")
        self.assertEqual(len(answer_history1), 2, "Should have 2 entries in answer_history1, for the answer fand for the arbitration")


        h_arr1 = [answer_history1[1]['previous_history_hash'], answer_history1[0]['previous_history_hash']]
        bond_arr1 = [answer_history1[1]['bond'], answer_history1[0]['bond']]
        anser_arr1 = [answer_history1[1]['answerer'], answer_history1[0]['answerer']]
        ans_arr1 = [answer_history1[1]['answer'], answer_history1[0]['answer']]

        # Pass one of the arrays in the wrong order to prove it fails
        bond_arr_wrong1 = [answer_history1[0]['bond'], answer_history1[1]['bond']]

        h_arr2 = [answer_history2[1]['previous_history_hash'], answer_history2[0]['previous_history_hash']]
        bond_arr2 = [answer_history2[1]['bond'], answer_history2[0]['bond']]
        anser_arr2 = [answer_history2[1]['answerer'], answer_history2[0]['answerer']]
        ans_arr2 = [answer_history2[1]['answer'], answer_history2[0]['answer']]

        # Pass one of the arrays in the wrong order to prove it fails
        bond_arr_wrong2 = [answer_history2[0]['bond'], answer_history2[1]['bond']]

        # print(self.l2web3.eth.accounts)
        self.assertEqual(answer_history1[-2]['answerer'], self.L1_CHARLIE, "charlie gave the first answer for realityeth 1")
        self.assertEqual(answer_history2[-2]['answerer'], self.L1_CHARLIE, "charlie gave the first answer for realityeth 2")
        self.assertEqual(answer_history1[-1]['answerer'], self.L1_CHARLIE, "charlie is credited with the answer for realityeth1")
        self.assertEqual(answer_history2[-1]['answerer'], self.L1_BOB, "bob is credited with the answer for realityeth2")

        with self.assertRaises(TransactionFailed):
            txid = realityeth2.functions.claimWinnings(contest_question_id, h_arr2, anser_arr2, bond_arr_wrong2, ans_arr2).transact(self._txargs(sender=self.L1_CHARLIE))
            self.raiseOnZeroStatus(txid, self.l1web3)

        charlie_before_bal = realityeth1.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertEqual(charlie_before_bal, 0, "Charlie has no balance on the forked reality.eth until claim")
        txid = realityeth1.functions.claimWinnings(contest_question_id, h_arr1, anser_arr1, bond_arr1, ans_arr1).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)
        charlie_after_bal = realityeth1.functions.balanceOf(self.L1_CHARLIE).call()
        self.assertNotEqual(charlie_after_bal, 0, "Charlie has a balance on the forked reality.eth after claim")

        txid = realityeth1.functions.withdraw().transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        self.assertEqual(realityeth1.functions.balanceOf(self.L1_CHARLIE).call(), 0, "After withdraw charlie no longer has tokens in the reality.eth contract")
        self.assertEqual(charlie_after_bal, child_fm1.functions.balanceOf(self.L1_CHARLIE).call(), "The balance charlie had on the reaity.eth1 is now in forkmanager1")

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_uncontested_bridge_upgrade(self):

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade()

        # We can't execute the bridge upgrade until the timeout
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)

        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(604800+10, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertTrue(ts2 >= ts1+604800+10, "Clock did not advance as expected")

        self.assertEqual(timeout, self.l1realityeth.functions.getTimeout(upgrade_question_id).call(), "Timeout reported by reality.eth not what we expect")

        history_hash = self.l1realityeth.functions.getHistoryHash(upgrade_question_id).call()
        self.assertNotEqual(history_hash, answer_history[-1]['previous_history_hash'])

        self.l1realityeth.functions.finalize(upgrade_question_id).transact()
        result1 = self.l1realityeth.functions.resultFor(upgrade_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(1))

        old_bridge = self.forkmanager.functions.bridgeToL2().call()

        txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        new_bridge = self.forkmanager.functions.bridgeToL2().call()
        self.assertNotEqual(old_bridge, new_bridge)

        self.assertEqual(new_bridge_created.address, new_bridge)



    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_successful_bridge_upgrade_with_freeze_and_unfreeze(self):

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        self.assertNotEqual(required_bridges[0], NULL_ADDRESS, "In the normal unfrozen unforked state there should be 1 bridge")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "In the normal unfrozen unforked state there should be only 1 bridge")

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade_up_to_freeze()

        # TODO: Test how TokenBridge consumes this data

        bond_after_freeze = self.l1realityeth.functions.getBond(upgrade_question_id).call() * 2
        self.assertTrue(bond_after_freeze > 0, "zero bond after freeze")

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, bond_after_freeze).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, bond_after_freeze).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.l1realityeth.functions.submitAnswerERC20(upgrade_question_id, to_answer_for_contract(1), 0, bond_after_freeze).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)

        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(timeout+10, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertTrue(ts2 >= ts1+604800+10, "Clock did not advance as expected")

        # Bridge upgrade should fail as the question is still open
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        self.l1realityeth.functions.finalize(upgrade_question_id).transact()

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        self.assertEqual(required_bridges[0], NULL_ADDRESS, "Bridges should be frozen, so none are acceptable")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "Bridges should be frozen, so none are acceptable")

        txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        self.assertNotEqual(required_bridges[0], NULL_ADDRESS, "In the normal unfrozen unforked state there should be 1 bridge")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "In the normal unfrozen unforked state there should be only 1 bridge")

        self.assertEqual(new_bridge_created.address, required_bridges[0], "The new bridge is now required")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_failed_bridge_upgrade_with_freeze_and_unfreeze(self):

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        original_bridge = required_bridges[0]
        self.assertNotEqual(required_bridges[0], NULL_ADDRESS, "In the normal unfrozen unforked state there should be 1 bridge")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "In the normal unfrozen unforked state there should be only 1 bridge")

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade_up_to_freeze()

        # TODO: Test how TokenBridge consumes this data

        bond_after_freeze = self.l1realityeth.functions.getBond(upgrade_question_id).call() * 2
        self.assertTrue(bond_after_freeze > 0, "zero bond after freeze")

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, bond_after_freeze).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, bond_after_freeze).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.l1realityeth.functions.submitAnswerERC20(upgrade_question_id, to_answer_for_contract(0), 0, bond_after_freeze).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)

        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(timeout+10, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertTrue(ts2 >= ts1+604800+10, "Clock did not advance as expected")

        # Bridge upgrade should fail as the question is still open
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        self.l1realityeth.functions.finalize(upgrade_question_id).transact()

        # Bridge upgrade should fail as the question came out as 0
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        self.assertEqual(required_bridges[0], NULL_ADDRESS, "Bridges should be frozen, so none are acceptable")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "Bridges should be frozen, so none are acceptable")

        # Since the proposition failed, we can clear it and go back to normal
        txid = self.forkmanager.functions.clearFailedGovernanceProposal(upgrade_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        required_bridges = self.forkmanager.functions.requiredBridges().call()
        self.assertNotEqual(required_bridges[0], NULL_ADDRESS, "In the normal unfrozen unforked state there should be 1 bridge")
        self.assertEqual(required_bridges[1], NULL_ADDRESS, "In the normal unfrozen unforked state there should be only 1 bridge")

        self.assertEqual(required_bridges[0], original_bridge, "The original bridge should be the only required one")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_uncontested_bridge_upgrade_with_freeze(self):

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade_up_to_freeze()

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)

        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(timeout+10, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertTrue(ts2 >= ts1+604800+10, "Clock did not advance as expected")

        # TODO: Check the bridge is frozen somehow

        self.l1realityeth.functions.finalize(upgrade_question_id).transact()
        result1 = self.l1realityeth.functions.resultFor(upgrade_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(1))

        old_bridge = self.forkmanager.functions.bridgeToL2().call()

        txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        new_bridge = self.forkmanager.functions.bridgeToL2().call()
        self.assertNotEqual(old_bridge, new_bridge)

        self.assertEqual(new_bridge_created.address, new_bridge)






    def _setup_bridge_upgrade_up_to_freeze(self):

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade()

        # We can't execute the bridge upgrade until the timeout
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)


        amount_to_freeze = self.forkmanager.functions.numTokensRequiredToFreezeBridges().call()
        self.assertTrue(amount_to_freeze > 1, "weird not to need any tokens to freeze bridges")

        self.assertTrue(amount_to_freeze > 12345, "amount to freeze better be more than we put in the original bond or the next tests we do will go wrong")

        # We can't execute the bridge upgrade until the bond is high enough
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.freezeBridges(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        # TODO: We should really be sending a proof that a high enough bond was submitted for the answer in question, not just any answer
 
        txid = self.forkmanager.functions.transfer(self.L1_BOB, amount_to_freeze).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, amount_to_freeze).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.l1realityeth.functions.submitAnswerERC20(upgrade_question_id, to_answer_for_contract(1), 0, amount_to_freeze).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.freezeBridges(upgrade_question_id).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)

        # TODO: Add this answer to answer_history

        return (upgrade_question_id, answer_history, new_bridge_created) 





    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_failed_bridge_upgrade(self):

        (upgrade_question_id, answer_history, new_bridge_created) = self._setup_bridge_upgrade()

        txid = self.forkmanager.functions.transfer(self.L1_BOB, 12345*2).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, 12345*2).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.l1realityeth.functions.submitAnswerERC20(upgrade_question_id, to_answer_for_contract(0), 0, 12345*2).transact(self._txargs(sender=self.L1_BOB))
        self.raiseOnZeroStatus(txid, self.l1web3)

        timeout = self.forkmanager.functions.REALITY_ETH_TIMEOUT().call()
        self.assertEqual(604800, timeout)

        ts1 = self._block_timestamp(self.l1web3)
        self._advance_clock(604800+10, self.l1web3)
        ts2 = self._block_timestamp(self.l1web3)
        self.assertTrue(ts2 >= ts1+604800+10, "Clock did not advance as expected")

        self.l1realityeth.functions.finalize(upgrade_question_id).transact()
        result1 = self.l1realityeth.functions.resultFor(upgrade_question_id).call()
        self.assertEqual(result1, to_answer_for_contract(0))

        old_bridge = self.forkmanager.functions.bridgeToL2().call()

        # Bridge upgrade should fail because the reality.eth question resulted in 0
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        new_bridge = self.forkmanager.functions.bridgeToL2().call()
        self.assertEqual(old_bridge, new_bridge, "Bridge should not change if the reality.eth question results in 0")

        self.assertNotEqual(new_bridge_created.address, new_bridge)


    






 




    # Do the bridge upgrade up to the point before we execute it
    # We can then test the execution path and the contest path separately
    def _setup_bridge_upgrade(self):

        newBridgeToL2 = self._contractFromBuildJSON(self.l1web3, 'BridgeToL2', None, None)
        txid = self.forkmanager.functions.beginUpgradeBridge(newBridgeToL2.address).transact()
        self.raiseOnZeroStatus(txid, self.l1web3)
        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)

        ask_log = self.l1realityeth.events.LogNewQuestion().process_receipt(tx_receipt)
        upgrade_question_id = ask_log[0]['args']['question_id']
        #upgrade_question_id = Web3.to_bytes(hexstr="0x"+encode_hex(ask_log[0]['args']['question_id']))

        upgradeq = self.l1realityeth.functions.questions(upgrade_question_id).call()
        last_history_hash = upgradeq[QINDEX_HISTORY_HASH]

        # We can't execute the bridge upgrade yet because there's no answer set
        with self.assertRaises(TransactionFailed):
            txid = self.forkmanager.functions.executeBridgeUpgrade(upgrade_question_id).transact()
            self.raiseOnZeroStatus(txid, self.l1web3)

        answer_history = []

        txid = self.forkmanager.functions.transfer(self.L1_CHARLIE, 12345).transact(self._txargs(sender=self.FORKMANAGER_INITIAL_RECIPIENT))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.forkmanager.functions.approve(self.l1realityeth.address, 12345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        txid = self.l1realityeth.functions.submitAnswerERC20(upgrade_question_id, to_answer_for_contract(1), 0, 12345).transact(self._txargs(sender=self.L1_CHARLIE))
        self.raiseOnZeroStatus(txid, self.l1web3)

        tx_receipt = self.l1web3.eth.get_transaction_receipt(txid)
        ans_log = self.l1realityeth.events.LogNewAnswer().process_receipt(tx_receipt)

        answer_history.append(self._log_to_answer_history(ans_log, last_history_hash))
        # self.assertNotEqual(last_history_hash, ans_log['history_hash'])

        return (upgrade_question_id, answer_history, newBridgeToL2)


        
class OldThing:


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_fund_increase(self):

        k0 = self.l2web3.eth.accounts[0]

        if ERC20:
            start_bal = self.l2token0.functions.balanceOf(k0).call()

            self.rc0.functions.fundAnswerBountyERC20(self.question_id
            ,500
            ).transact()

            end_bal = self.l2token0.functions.balanceOf(k0).call()
            self.assertEqual(end_bal, start_bal - 500)
        else:
            txargs = self.standard_tx
            txargs['value'] = 500
            self.rc0.functions.fundAnswerBounty(self.question_id).transact(txargs)

        question = self.rc0.functions.questions(self.question_id).call()
        self.assertEqual(question[QINDEX_BOUNTY], 1500)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_no_response_finalization(self):
        # Should not be final if too soon
        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        self._advance_clock(33)
        
        # Should not be final if there is no answer
        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_simple_response_finalization(self):

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0 ,1).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1))

        self._advance_clock(33)

        best_answer = self.rc0.functions.questions(self.question_id).call()[QINDEX_BEST_ANSWER]
        self.assertEqual(12345, from_answer_for_contract(best_answer))

        self.assertTrue(self.rc0.functions.isFinalized(self.question_id).call())

        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 12345)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_content_hash(self):
        expect_ch = calculate_content_hash(0, "my question", 0)
        ch = "0x" + self.rc0.functions.questions(self.question_id).call()[QINDEX_CONTENT_HASH]
        self.assertEqual(expect_ch, ch)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_get_final_answer_if_match(self):

        expect_ch = calculate_content_hash(0, "my question", 0)
        wrong_ch = calculate_content_hash(0, "not my question", 0)

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0 ,1
            ).transact()

        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1) )

        # Not finalized yet
        with self.assertRaises(TransactionFailed):
            ans = self.rc0.functions.getFinalAnswerIfMatches(
                self.question_id,
                decode_hex(expect_ch[2:]),
                self.arb0.address,
                0,
                25
            ).call()

        self._advance_clock(33)

        with self.assertRaises(TransactionFailed):
            self.rc0.functions.getFinalAnswerIfMatches(
                self.question_id,
                decode_hex(expect_ch[2:]),
                keys.privtoaddr(t.k2),
                0,
                25
            ).call()

        with self.assertRaises(TransactionFailed):
            self.rc0.functions.getFinalAnswerIfMatches(
                self.question_id,
                decode_hex(wrong_ch[2:]),
                self.arb0.address,
                0,
                25
            ).call()

        with self.assertRaises(TransactionFailed):
            self.rc0.functions.getFinalAnswerIfMatches(
                self.question_id,
                decode_hex(expect_ch[2:]),
                self.arb0.address,
                25,
                99999999999
            ).call()

        with self.assertRaises(TransactionFailed):
            self.rc0.functions.getFinalAnswerIfMatches(
                self.question_id,
                decode_hex(expect_ch[2:]),
                self.arb0.address,
                1893459661, # 2030-01-01
                25
            ).call()

        ans = self.rc0.functions.getFinalAnswerIfMatches(
            self.question_id,
            decode_hex(expect_ch[2:]),
            self.arb0.address,
            0,
            0
        ).call()
        self.assertEqual(from_answer_for_contract(ans), 12345)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_earliest_finalization_ts(self):

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(54321), 0 ,10).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(54321), 0).transact(self._txargs(val=10))
        ts1 = self.rc0.functions.questions(self.question_id).call()[QINDEX_FINALIZATION_TS]

        self._advance_clock(1)

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(54321), 0 ,20).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(54321), 0).transact(self._txargs(val=20))

        self.assertEqual(self.rc0.functions.questions(self.question_id).call()[QINDEX_BOND], 20)
        ts2 = self.rc0.functions.questions(self.question_id).call()[QINDEX_FINALIZATION_TS]

        self.assertTrue(ts2 > ts1, "Submitting an answer advances the finalization timestamp") 

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_conflicting_response_finalization(self):

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1
            ).transact()
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(54321), 0,
            10
            ).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1)) 
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(54321), 0).transact(self._txargs(val=10))

        self._advance_clock(33)

        self.assertTrue(self.rc0.functions.isFinalized(self.question_id).call())
        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 54321)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_answered(self):

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1
            ).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1))

        # The arbitrator cannot submit an answer that has not been requested. 
        # (If they really want to do this, they can always pay themselves for arbitration.)
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), keys.privtoaddr(t.k0)).transact() 

        # You cannot notify realitio of arbitration unless you are the arbitrator
        with self.assertRaises(TransactionFailed):
            self.rc0.functions.notifyOfArbitrationRequest(self.question_id, keys.privtoaddr(t.k0), 0).transact() 

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")
        question = self.rc0.functions.questions(self.question_id).call()
        self.assertTrue(question[QINDEX_IS_PENDING_ARBITRATION], "When arbitration is pending for an answered question, we set the is_pending_arbitration flag to True")
        self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), keys.privtoaddr(t.k0)).transact()

        self.assertTrue(self.rc0.functions.isFinalized(self.question_id).call())
        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 123456, "Arbitrator submitting final answer calls finalize")

        self.assertNotEqual(self.rc0.functions.questions(self.question_id).call()[QINDEX_BOND], 0)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_assigning_answerer_right(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_answering_assigning_answerer_right, not a feature of this contract")
            return

        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)

        last_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4)

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")

        arb_answer = to_answer_for_contract(1001)
        arb_payer = keys.privtoaddr(t.k2)

        hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        # Only the arbitrator can do this
        with self.assertRaises(TransactionFailed):
            self.rc0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, arb_answer)
        st['addr'].insert(0, k4)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 2+subfee(4)+subfee(8)+subfee(16)+1000, "The last answerer gets it all for a right answer")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_assigning_answerer_right_commit(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_answering_assigning_answerer_right_commit, not a feature of this contract")
            return

        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)

        last_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4, True)
        nonce = st['nonce'][0]
        self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1001), nonce, 16).transact(self._txargs(sender=k4, val=0))

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")

        arb_answer = to_answer_for_contract(1001)
        arb_payer = keys.privtoaddr(t.k2)

        hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, arb_answer)
        st['addr'].insert(0, k4)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 2+subfee(4)+subfee(8)+subfee(16)+1000, "The last answerer gets it all for a right answer")

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_assigning_answerer_wrong_commit(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_answering_assigning_answerer_wrong_commit, not a feature of this contract")
            return

        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)

        last_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4, True)
        nonce = st['nonce'][0]
        self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1001), nonce, 16).transact(self._txargs(sender=k4, val=0))

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")

        arb_answer = to_answer_for_contract(98765)
        arb_payer = keys.privtoaddr(t.k2)

        hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, arb_answer)
        st['addr'].insert(0, arb_payer)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(arb_payer).call(), 2+subfee(4)+subfee(8)+subfee(16)+1000, "The last answerer gets it all for a right answer")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_assigning_answerer_wrong(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_answering_assigning_answerer_wrong, not a feature of this contract")
            return

        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)

        last_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4)

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")

        arb_answer = to_answer_for_contract(123456)
        arb_payer = keys.privtoaddr(t.k2)

        hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, arb_answer)
        st['addr'].insert(0, arb_payer)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(arb_payer).call(), 2+subfee(4)+subfee(8)+subfee(16)+1000, "The arb payer gets it all for a wrong answer")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_assigning_answerer_unrevealed_commit(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_answering_assigning_answerer_unrevealed_commit, not a feature of this contract")
            return

        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)

        last_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 0, 8, 16, k4, True)

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")

        arb_answer = to_answer_for_contract(0)
        arb_payer = keys.privtoaddr(t.k2)

        ##self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(st['answer'][-1], to_answer_for_contract(1001))
        hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]

        # Arbitration fails if the reveal timeout has not come yet
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        self._advance_clock(10)
        self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, arb_answer, arb_payer, st['hash'][0], st['answer'][0], st['addr'][0] ).transact() 

        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, arb_answer)
        st['addr'].insert(0, arb_payer)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(arb_payer).call(), 2+subfee(4)+subfee(8)+subfee(16)+1000, "The arb payer gets it all for a wrong answer")


        return

        # The arbitrator cannot submit an answer that has not been requested. 
        # (If they really want to do this, they can always pay themselves for arbitration.)
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.assignWinnerAndSubmitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), keys.privtoaddr(t.k0)).transact() 

        # You cannot notify realitio of arbitration unless you are the arbitrator
        with self.assertRaises(TransactionFailed):
            self.rc0.functions.notifyOfArbitrationRequest(self.question_id, keys.privtoaddr(t.k0), 0).transact() 

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")
        question = self.rc0.functions.questions(self.question_id).call()
        #self.assertEqual(question[QINDEX_FINALIZATION_TS], 1, "When arbitration is pending for an answered question, we set the finalization_ts to 1")
        self.assertTrue(question[QINDEX_IS_PENDING_ARBITRATION], "When arbitration is pending for an answered question, we set the is_pending_arbitration flag to True")
        self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), keys.privtoaddr(t.k0)).transact()

        self.assertTrue(self.rc0.functions.isFinalized(self.question_id).call())
        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 123456, "Arbitrator submitting final answer calls finalize")

        self.assertNotEqual(self.rc0.functions.questions(self.question_id).call()[QINDEX_BOND], 0)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_single_unrevealed_commit(self):

        if VERNUM < 3.0:
            print("Skipping test_arbitrator_answering_assigning_answerer_single_unrevealed_commit, not a feature of this contract")
            return

        k0 = self.l2web3.eth.accounts[0]
        k2 = self.l2web3.eth.accounts[2]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 100000, 50000)
            self._issueTokens(self.l2token1, k3, 100000, 50000)
            self._issueTokens(self.l2token1, k4, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4, True)
        nonce = st['nonce'][0]

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        txid = self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))
        with self.assertRaises(TransactionFailed):
            self.raiseOnZeroStatus(txid)

        txid = self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1001), nonce, 2).transact(self._txargs(sender=k4))
        self.raiseOnZeroStatus(txid)

        txid = self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))
        self.raiseOnZeroStatus(txid)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_cancel(self):

        if VERNUM < 2.1:
            print("Skipping test_arbitrator_cancel, not a feature of this contract")
            return

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0, 1).transact(self._txargs())
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1))

        # The arbitrator cannot submit an answer that has not been requested. 
        # (If they really want to do this, they can always pay themselves for arbitration.)
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), keys.privtoaddr(t.k0)).transact() 

        # The arbitrator cannot cancel arbitration that has not been requested
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.cancelArbitration(self.question_id).transact()

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration")
        question = self.rc0.functions.questions(self.question_id).call()
        #self.assertEqual(question[QINDEX_FINALIZATION_TS], 1, "When arbitration is pending for an answered question, we set the finalization_ts to 1")
        self.assertTrue(question[QINDEX_IS_PENDING_ARBITRATION], "When arbitration is pending for an answered question, we set the is_pending_arbitration flag to True")

        # Only the arbitrator can cancel arbitration
        with self.assertRaises(TransactionFailed):
            self.rc0.functions.cancelArbitration(self.question_id).transact()
        
        cancelled_ts = self._block_timestamp()
        self.arb0.functions.cancelArbitration(self.question_id).transact();
        question = self.rc0.functions.questions(self.question_id).call()

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        # The arbitrator cannot cancel arbitration again as it is no longer pending arbitratin
        with self.assertRaises(TransactionFailed):
            self.arb0.functions.cancelArbitration(self.question_id).transact()

        self.assertFalse(question[QINDEX_IS_PENDING_ARBITRATION], "When arbitration has been cancelled, is_pending_arbitration flag is set back to False")
        self.assertEqual(question[QINDEX_FINALIZATION_TS], cancelled_ts + 30, "Cancelling arbitration extends the timeout")

        # You can submit answers again
        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(54321), 0, 2).transact(self._txargs())
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(54321), 0).transact(self._txargs(val=2))

        # You can request arbitration again
        self.assertTrue(self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee)), "Requested arbitration again")


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_answering_unanswered(self):

        with self.assertRaises(TransactionFailed):
            self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(123456), self.arb0.address).transact() 

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())
        self.assertEqual(self.rc0.functions.questions(self.question_id).call()[QINDEX_BOND], 0)

        fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()

        # TODO: This doesn't do anything, which is OK, but why doesn't it raise a TransactionFailed??
        #with self.assertRaises(TransactionFailed):
        self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))

        self.assertFalse(self.rc0.functions.questions(self.question_id).call()[QINDEX_IS_PENDING_ARBITRATION])

    def submitAnswerReturnUpdatedState(self, st, qid, ans, max_last, bond, sdr, is_commitment = False, is_arbitrator = False, skip_sender = False, tx_acct = None):

        if tx_acct is None:
            tx_acct = sdr

        if st is None:
            st = {
                'addr': [],
                'bond': [],
                'answer': [],
                'hash': [],
                'nonce': [], # only for commitments
            }

        # ANSWERED_TOO_SOON_VAL is already encoded
        # For anything else we pass in an int which we should hex-encode
        if ans == ANSWERED_TOO_SOON_VAL:
            encoded_ans = ans
        else:
            encoded_ans = to_answer_for_contract(ans)

        hist_hash = self.rc0.functions.questions(qid).call()[QINDEX_HISTORY_HASH]
        st['hash'].insert(0, hist_hash)
        st['bond'].insert(0, bond)
        st['answer'].insert(0, encoded_ans)
        st['addr'].insert(0, sdr)
        nonce = None
        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        if ERC20:

            if is_commitment:
                nonce = 1234
                answer_hash = calculate_answer_hash(encoded_ans, nonce)
                commitment_id = calculate_commitment_id(decode_hex(self.question_id[2:]), decode_hex(answer_hash[2:]), bond)
                if skip_sender:
                    txid = self.rc0.functions.submitAnswerCommitmentERC20(qid, decode_hex(answer_hash[2:]), max_last, NULL_ADDRESS
                    ,bond
                    ).transact(self._txargs(sender=tx_acct))
                    self.raiseOnZeroStatus(txid)
                else:
                    txid = self.rc0.functions.submitAnswerCommitmentERC20(qid, decode_hex(answer_hash[2:]), max_last, sdr
                    ,bond
                    ).transact(self._txargs(sender=tx_acct))
                    self.raiseOnZeroStatus(txid)
                st['answer'][0] = decode_hex(commitment_id[2:])
            else:
                if is_arbitrator:
                    txid = self.arb0.functions.submitAnswerByArbitrator(qid, encoded_ans, 0, 0, sdr).transact(self._txargs(sender=tx_acct))
                    self.raiseOnZeroStatus(txid)
                else:
                    txid = self.rc0.functions.submitAnswerERC20(qid, encoded_ans, max_last
                    ,bond
                    ).transact(self._txargs(sender=tx_acct))
                    self.raiseOnZeroStatus(txid)

        else:

            if is_commitment:
                nonce = 1234
                answer_hash = calculate_answer_hash(encoded_ans, nonce)
                commitment_id = calculate_commitment_id(decode_hex(self.question_id[2:]), decode_hex(answer_hash[2:]), bond)
                #self.assertEqual(to_answer_for_contract(ans), commitment_id)
                if skip_sender:
                    self.rc0.functions.submitAnswerCommitment(qid, decode_hex(answer_hash[2:]), max_last, NULL_ADDRESS).transact(self._txargs(val=bond, sender=sdr))
                else:
                    self.rc0.functions.submitAnswerCommitment(qid, decode_hex(answer_hash[2:]), max_last, sdr).transact(self._txargs(val=bond, sender=sdr))
                st['answer'][0] = decode_hex(commitment_id[2:])
            else:
                if is_arbitrator:
                    self.arb0.functions.submitAnswerByArbitrator(qid, encoded_ans, 0, 0, sdr).transact(self._txargs(val=bond, sender=sdr))
                else:
                    self.rc0.functions.submitAnswer(qid, encoded_ans, max_last).transact(self._txargs(val=bond, sender=sdr))

        st['nonce'].insert(0, nonce)
        return st


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_same_person_repeating_self(self):
        st = None

        sdr = self.l2web3.eth.accounts[3]

        if ERC20:
            self._issueTokens(self.l2token1, sdr, 100000, 50000)

        ##hist_hash = self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH]
        ##self.assertEqual(hist_hash, '0x0000000000000000000000000000000000000000000000000000000000000000')
        ##st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, t.k3)
        ##self.assertEqual(st['hash'][0], hist_hash)
        ##sdr = self.l2web3.eth.accounts[0]

        ##bond = 1
        ##ans = 0
        ##qid = self.question_id
        ##max_last = 0
        ##self.rc0.functions.submitAnswer(qid, to_answer_for_contract(ans), max_last).transact(self._txargs(val=bond, sender=sdr))
        ##new_hist_hash = "0x"+encode_hex(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        ##new_hash = calculate_history_hash(hist_hash, to_answer_for_contract(ans), bond, sdr, False)
        ##self.assertEqual(new_hash, new_hist_hash)
        
        ##self._advance_clock(33)
        ##self.rc0.functions.claimWinnings(self.question_id, [hist_hash], [sdr], [bond], [to_answer_for_contract(ans)]).transact()
        ##return

        ##print(st)

        ##self._advance_clock(33)
        ##self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        ##return

        #hist_hash = "0x" + encode_hex(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 20, sdr)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 20, 40, sdr)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 40, 80, sdr)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 80, 160, sdr)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 160, 320, sdr)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 320, 640, sdr)
        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(sdr).call(), 640+subfee(320)+subfee(160)+subfee(80)+subfee(40)+subfee(20)+1000)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_same_person_contradicting_self(self):
        k3 = self.l2web3.eth.accounts[3]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 20, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 20, 40, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 40, 80, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1004, 80, 160, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1003, 160, 320, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 320, 640, k3)
        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 640+subfee(320)+subfee(160)+subfee(80)+subfee(40)+subfee(20)+1000)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_subfee(self):
        if CLAIM_FEE == 0:
            return
        else:
            self.assertEqual(subfee(100), 98)
            self.assertEqual(subfee(1), 1)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_set_dispute_fee(self):

        # fee of 0 should mean you can never request arbitration
        self.arb0.functions.setDisputeFee(0).transact()
        with self.assertRaises(TransactionFailed):
            fee = self.arb0.functions.getDisputeFee(decode_hex("0x00")).call()
            txid = self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))
            self.raiseOnZeroStatus(txid)

        self.arb0.functions.setDisputeFee(123).transact()
        self.assertEqual(self.arb0.functions.getDisputeFee(self.question_id).call(), 123)

        # question-specific fee should work for that question
        self.arb0.functions.setCustomDisputeFee(self.question_id, 23).transact()
        self.assertEqual(self.arb0.functions.getDisputeFee(self.question_id).call(), 23)

        # removing custom fee should resurrect the default fee
        self.arb0.functions.setCustomDisputeFee(self.question_id, 0).transact()
        self.assertEqual(self.arb0.functions.getDisputeFee(self.question_id).call(), 123)
        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitration_max_previous(self):
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
            

        fee = self.arb0.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()
        with self.assertRaises(TransactionFailed):
            txid = self.arb0.functions.requestArbitration(self.question_id, 2).transact(self._txargs(val=fee))
            self.raiseOnZeroStatus(txid)
        self.arb0.functions.requestArbitration(self.question_id, 4).transact(self._txargs(val=fee))
        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_arbitration_existing_none(self):
        fee = self.arb0.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()
        with self.assertRaises(TransactionFailed):
            txid = self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))
            self.raiseOnZeroStatus(txid)
        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_arbitration_existing_final(self):
        fee = self.arb0.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4)

        self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))

        st['hash'].insert(0, self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        st['addr'].insert(0, k4)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, to_answer_for_contract(1001))
        self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(1001), k4).transact() 

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 16+8+4+2+1000)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_split_over_transactions(self):

        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4)

        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'][:2], st['addr'][:2], st['bond'][:2], st['answer'][:2]).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 16+1000)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'][2:], st['addr'][2:], st['bond'][2:], st['answer'][2:]).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 16+8+4+2+1000)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_after_reveal_fail(self):

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k6 = self.l2web3.eth.accounts[6]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k6, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001,  1,  2, k5, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1003,  2,  4, k4, False) 
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  4,  8, k6, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1004,  8, 16, k5, True)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 16, 32, k4, True)
    
        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k6).call(), 32+16+8+4+2-1+1000)
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 1+1)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_split_over_transactions_payee_later(self):

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k6 = self.l2web3.eth.accounts[6]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k6, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001,  1,  2, k5, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1003,  2,  4, k4, False) 
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  4,  8, k6, False)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1004,  8, 16, k5, True)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 16, 32, k4, True)

        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, st['hash'][:2], st['addr'][:2], st['bond'][:2], st['answer'][:2]).transact()
        self.rc0.functions.claimWinnings(self.question_id, st['hash'][2:], st['addr'][2:], st['bond'][2:], st['answer'][2:]).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k6).call(), 32+16+8+4+2-1+1000)
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 1+1)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_reveal_calculation(self):
        h = calculate_answer_hash(to_answer_for_contract(1003), 94989)
        self.assertEqual(h, '0x23e796d2bf4f5f890b1242934a636f4802aadd480b6f83c754d2bd5920f78845')

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_commit_normal(self):

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k6 = self.l2web3.eth.accounts[6]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k6, 1000000, 1000000)

        self.l2web3.testing.mine()
        self.assertEqual(self.rc0.functions.questions(self.question_id).call()[QINDEX_STEP_DELAY], 30)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, True)
        nonce = st['nonce'][0]
        hh = st['hash'][0]
        commitment_id = st['answer'][0]

        comm = self.rc0.functions.commitments(commitment_id).call()
        reveal_ts = comm[0]
        self.assertTrue(reveal_ts > 0)

        self.l2web3.testing.mine()
        self.assertTrue(reveal_ts > self._block_timestamp())

        with self.assertRaises(TransactionFailed):
            q = self.rc0.functions.getFinalAnswer(self.question_id).call()

        #print(self.rc0.functions.questions(self.question_id).call())
        txid = self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1002), nonce, 1).transact(self._txargs(sender=k3, val=0))

        comm = self.rc0.functions.commitments(commitment_id).call()
        reveal_ts = comm[0]
        is_revealed = comm[1]
        revealed_answer = comm[2]
        self.assertTrue(reveal_ts > 0)
        self.assertTrue(is_revealed)
        self.assertEqual(revealed_answer, to_answer_for_contract(1002))


        self.raiseOnZeroStatus(txid)

        #rcp = self.l2web3.eth.get_transaction_receipt(txid)
        self._advance_clock(33)
        #time.sleep(10)

        q = self.rc0.functions.questions(self.question_id).call()[QINDEX_BEST_ANSWER]
        self.assertEqual(from_answer_for_contract(q), 1002)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 1001)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_commit_skip_sender(self):
        st = None

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k6 = self.l2web3.eth.accounts[6]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k6, 1000000, 1000000)

        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, True, False, True)
        nonce = st['nonce'][0]
        hh = st['hash'][0]

        with self.assertRaises(TransactionFailed):
            q = self.rc0.functions.getFinalAnswer(self.question_id).call()

        self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1002), nonce, 1).transact(self._txargs(sender=k3, val=0))

        self._advance_clock(33)

        q = self.rc0.functions.getFinalAnswer(self.question_id).call()
        self.assertEqual(from_answer_for_contract(q), 1002)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 1001)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_no_answer_no_commit(self):

        k3 = self.l2web3.eth.accounts[3]
        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, True)
        nonce = st['nonce'][0]
        hh = st['hash'][0]

        with self.assertRaises(TransactionFailed):
            q = self.rc0.functions.getFinalAnswer(self.question_id).call()

        self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1002), nonce, 1).transact(self._txargs(sender=k3, val=0))
        self._advance_clock(33)

        q = self.rc0.functions.getFinalAnswer(self.question_id).call()
        self.assertEqual(from_answer_for_contract(q), 1002)

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 1001)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_commit_expired(self):

        k3 = self.l2web3.eth.accounts[3]
        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, True)
        nonce = st['nonce'][0]
        hh = st['hash'][0]

        self._advance_clock(5)
        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1002), nonce, 1).transact(self._txargs(sender=k3, val=0))
            self.raiseOnZeroStatus(txid)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_commit_with_arbitration_pending(self):
    
        k3 = self.l2web3.eth.accounts[3]
        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000, 1000)

        fee = self.arb0.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002,  0,  1, k3, True)
        nonce = st['nonce'][0]
        hh = st['hash'][0]

        self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))

        #with self.assertRaises(TransactionFailed):
        st = self.rc0.functions.submitAnswerReveal( self.question_id, to_answer_for_contract(1002), nonce, 1).transact(self._txargs(sender=k3, val=0))


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_token_deductions_no_balance(self):

        if not ERC20:
            return

        k0 = self.l2web3.eth.accounts[0]
        k3 = self.l2web3.eth.accounts[3]
        bal = self.l2token0.functions.balanceOf(k3).call()
        self.assertEqual(bal, 0)

        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1000
            ).transact(self._txargs(sender=k3))
            self.raiseOnZeroStatus(txid)

        self._issueTokens(self.l2token1, k3, 500, 500)

        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1000
            ).transact(self._txargs(sender=k3))
            self.raiseOnZeroStatus(txid)

        self._issueTokens(self.l2token1, k3, 501, 1001)

        bal = self.l2token0.functions.balanceOf(k3).call()
        self.assertEqual(bal, 1001)

        txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
        ,1000
        ).transact(self._txargs(sender=k3))
        self.raiseOnZeroStatus(txid)

        bal = self.l2token0.functions.balanceOf(k3).call()
        self.assertEqual(bal, 1)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_token_deductions_with_existing_balance(self):

        if not ERC20:
            return

        k3 = self.l2web3.eth.accounts[3]
        self._setup_balance(k3, 1000)

        start_rcbal = self.rc0.functions.balanceOf(k3).call()
        start_tbal = self.l2token0.functions.balanceOf(k3).call()

        self.assertEqual(start_rcbal, 1000)

        # There's enough in the balance, so this will deduct from the balance and leave the token alone
        self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
        ,1
        ).transact(self._txargs(sender=k3))

        rcbal = self.rc0.functions.balanceOf(k3).call()
        self.assertEqual(rcbal, 999)
        tbal = self.l2token0.functions.balanceOf(k3).call()
        self.assertEqual(tbal, start_tbal)

        # Sets the approval to 500, and makes sure there at least 500
        self._issueTokens(self.l2token1, k3, 500, 500)
        start_tbal = self.l2token0.functions.balanceOf(k3).call()

        # We have 999 in the balance and only 500 approved, so this should fail
        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,2000
            ).transact(self._txargs(sender=k3))
            self.raiseOnZeroStatus(txid)


        start_tbal = self.l2token0.functions.balanceOf(k3).call()

        # This will consume all the remaining balance, plus take 1 from the token
        txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
        ,1000
        ).transact(self._txargs(sender=k3))
        self.raiseOnZeroStatus(txid)

        rcbal = self.rc0.functions.balanceOf(k3).call()
        self.assertEqual(rcbal, 0)
        tbal = self.l2token0.functions.balanceOf(k3).call()
        self.assertEqual(tbal, start_tbal - 1)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_claim_arbitration_existing_not_final(self):
    
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)

        fee = self.arb0.functions.getDisputeFee(Web3.to_bytes(hexstr=NULL_BYTES)).call()

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k4)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1002, 4, 8, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k4)

        self.arb0.functions.requestArbitration(self.question_id, 0).transact(self._txargs(val=fee))

        st['hash'].insert(0, self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        st['addr'].insert(0, k3)
        st['bond'].insert(0, 0)
        st['answer'].insert(0, to_answer_for_contract(1002))
        self.arb0.functions.submitAnswerByArbitrator(self.question_id, to_answer_for_contract(1002), k3).transact(self._txargs(val=0)) 

        self.rc0.functions.claimWinnings(self.question_id, st['hash'], st['addr'], st['bond'], st['answer']).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 16+8+4+2+1000)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_min_payment_with_bond_param(self):

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]

        if ERC20:

            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)

            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1
            ).transact()
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10001), 0
            ,2
            ).transact(self._txargs(sender=k3))
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10002), 0
            ,5
            ).transact(self._txargs(sender=k4))

            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10002), 5,
            22+5
            ).transact(self._txargs(sender=k5))

        else:

            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1))
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10001), 0).transact(self._txargs(val=2, sender=k3)) 
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10002), 0).transact(self._txargs(val=5, sender=k4)) 

            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10002), 5).transact(self._txargs(val=(22+5), sender=k5)) 

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_simple_bond_claim(self):

        k0 = self.l2web3.eth.accounts[0]

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,3
            ).transact()

        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=3)) 

        self._advance_clock(33)

        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 12345)

        self.rc0.functions.claimWinnings(self.question_id, [decode_hex("0x00")], [k0], [3], [to_answer_for_contract(12345)]).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k0).call(), 3+1000)
        self.assertEqual(self.rc0.functions.balanceOf(k0).call(), 3+1000, "Winner gets their bond back plus the bounty")

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bonds(self):

        k0 = self.l2web3.eth.accounts[0]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)

        claim_args_state = []
        claim_args_addrs = []
        claim_args_bonds = []
        claim_args_answs = []

        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), 0)

        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0,
                0
                ).transact()
            else:
                txid = self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=0)) 
                
            self.raiseOnZeroStatus(txid)

        claim_args_state.append(decode_hex("0x00"))
        claim_args_addrs.append(k0)
        claim_args_bonds.append(1)
        claim_args_answs.append(to_answer_for_contract(12345))

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1
            ).transact()
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1)) 
        

        # "You must increase"
        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10001), 0
                ,1
                ).transact(self._txargs(sender=k3))
            else:
                txid = self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10001), 0).transact(self._txargs(val=1, sender=k3)) 
            self.raiseOnZeroStatus(txid)

        claim_args_state.append(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        claim_args_addrs.append(k3)
        claim_args_bonds.append(2)
        claim_args_answs.append(to_answer_for_contract(10001))

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10001), 0
            ,2
            ).transact(self._txargs(sender=k3))
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10001), 0).transact(self._txargs(val=2, sender=k3))

        # We will ultimately finalize on this answer
        claim_args_state.append(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        claim_args_addrs.append(k4)
        claim_args_bonds.append(4)
        claim_args_answs.append(to_answer_for_contract(10002))

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10002), 0
            ,4
            ).transact(self._txargs(sender=k4))
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10002), 0).transact(self._txargs(val=4, sender=k4)) 

        if ERC20:
            # You have to at least double
            with self.assertRaises(TransactionFailed):
                self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10003), 0
                ,7
                ).transact()

            # You definitely can't drop back to zero
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10004), 0
                ,0
                ).transact()
                self.raiseOnZeroStatus(txid)

        else:
            # You have to at least double
            ###with self.assertRaises(TransactionFailed):
            ###    self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10003), 0).transact(self._txargs(val=7)) 
            self.assertZeroStatus(self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10003), 0).transact(self._txargs(val=7)))

            # You definitely can't drop back to zero
            ###with self.assertRaises(TransactionFailed):
            ###    self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10004), 0).transact(self._txargs(val=0)) 
            self.assertZeroStatus(self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10004), 0).transact(self._txargs(val=0)))

        claim_args_state.append(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        claim_args_addrs.append(k3)
        claim_args_bonds.append(11)
        claim_args_answs.append(to_answer_for_contract(10005))

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10005), 0
            ,11
            ).transact(self._txargs(sender=k3))
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10005), 0).transact(self._txargs(val=11, sender=k3))

        # The extra amount you have to send should be passed in a parameters
        #with self.assertRaises(TransactionFailed): 
        #    self.rc0.submitAnswer(self.question_id, to_answer_for_contract(10002), 0, value=(22+5), sender=t.k5, startgas=200000) 

        claim_args_state.append(self.rc0.functions.questions(self.question_id).call()[QINDEX_HISTORY_HASH])
        claim_args_addrs.append(k5)
        claim_args_bonds.append(22)
        claim_args_answs.append(to_answer_for_contract(10002))

        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(10002), 11
            ,22
            ).transact(self._txargs(sender=k5))
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(10002), 11).transact(self._txargs(val=22, sender=k5)) 

        self.assertFalse(self.rc0.functions.isFinalized(self.question_id).call())

        #You can't claim the bond until the thing is finalized
        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.claimWinnings(self.question_id, claim_args_state[::-1], claim_args_addrs[::-1], claim_args_bonds[::-1], claim_args_answs[::-1]).transact()
            self.raiseOnZeroStatus(txid)

        self._advance_clock(33)

        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(self.question_id).call()), 10002)

        # First right answerer gets:
        #  - their bond back (4)
        #  - their bond again (4)
        #  - the accumulated bonds until their last answer (1 + 2)

        k4bal = 4 + 4 + 1 + 2
        self.rc0.functions.claimWinnings(self.question_id, claim_args_state[::-1], claim_args_addrs[::-1], claim_args_bonds[::-1], claim_args_answs[::-1]).transact()

        self.assertEqual(self.rc0.functions.balanceOf(k4).call(), k4bal, "First answerer gets double their bond, plus earlier bonds")

        # Final answerer gets:
        #  - their bond back (22)
        #  - the bond of the previous guy, who was wrong (11)
        #  - ...minus the payment to the lower guy (-4)
        k5bal = 22 + 11 - 4 + 1000
        self.assertEqual(self.rc0.functions.balanceOf(k5).call(), k5bal, "Final answerer gets the bounty, plus their bond, plus earlier bonds up to when they took over the answer, minus the bond of the guy lower down with the right answer")

        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 0, "Wrong answerers get nothing")

        if ERC20:
            starting_bal = self.l2token0.functions.balanceOf(k5).call()
        else:
            starting_bal = self.l2web3.eth.get_balance(k5)

        txid = self.rc0.functions.withdraw().transact(self._txargs(sender=k5))
        rcpt = self.l2web3.eth.get_transaction_receipt(txid)
        gas_spent = rcpt['cumulativeGasUsed']

        if ERC20:
            ending_bal = self.l2token0.functions.balanceOf(k5).call()
            self.assertEqual(ending_bal, starting_bal + k5bal)
        else:
            ending_bal = self.l2web3.eth.get_balance(k5)
            self.assertEqual(ending_bal, starting_bal + k5bal - gas_spent)

        self.assertEqual(self.rc0.functions.balanceOf(k5).call(), 0)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_bond_bulk_withdrawal_other_user(self):

        k3 = self.l2web3.eth.accounts[3]
        k5 = self.l2web3.eth.accounts[5]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 100000, 50000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 4, 8, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 16, 32, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 32, 64, k3)
        claimable = 64+32+16+8+4+2+1000

        self._advance_clock(33)

        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 0)

        # Have an unconnected user do the claim
        # This will leave the balance in the contract rather than withdrawing it
        self.rc0.functions.claimMultipleAndWithdrawBalance([self.question_id], [len(st['hash'])], st['hash'], st['addr'], st['bond'], st['answer']).transact(self._txargs(sender=k5))
        
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), claimable)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_withdrawal(self):

        k5 = self.l2web3.eth.accounts[5]
        
        if ERC20:
              self._issueTokens(self.l2token1, k5, 1000000, 1000000)
        
        if ERC20:
            self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,100
            ).transact(self._txargs(sender=k5))
        else:
            self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=100, sender=k5))
        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, [decode_hex("0x00")], [k5], [100], [to_answer_for_contract(12345)]).transact(self._txargs(sender=k5))

        starting_deposited = self.rc0.functions.balanceOf(k5).call()
        self.assertEqual(starting_deposited, 1100)

        gas_used = 0
        if ERC20:
            starting_bal = self.l2token0.functions.balanceOf(k5).call()
        else:
            starting_bal = self.l2web3.eth.get_balance(k5)

        txid = self.rc0.functions.withdraw().transact(self._txargs(sender=k5))
        rcpt = self.l2web3.eth.get_transaction_receipt(txid)
        gas_used = rcpt['cumulativeGasUsed']

        if ERC20:
            ending_bal = self.l2token0.functions.balanceOf(k5).call()
        else:
            ending_bal = self.l2web3.eth.get_balance(k5)

        self.assertEqual(self.rc0.functions.balanceOf(k5).call(), 0)

        if ERC20:
            self.assertEqual(ending_bal, starting_bal + starting_deposited)
        else:
            self.assertEqual(ending_bal, starting_bal + starting_deposited - gas_used)

        return

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_submit_answer_for_withdrawal(self):

        if VERNUM < 2.1:
            print("Skipping test_submit_answer_for_withdrawal, submitAnswerFor is not a feature of this contract")
            return

        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]

        if ERC20:
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
        
        if ERC20:
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.submitAnswerForERC20(self.question_id, to_answer_for_contract(12345), 0, "0x0000000000000000000000000000000000000000", 100).transact(self._txargs(sender=k4))
                self.raiseOnZeroStatus(txid)
        else:
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.submitAnswerFor(self.question_id, to_answer_for_contract(12345), 0, "0x0000000000000000000000000000000000000000").transact(self._txargs(val=100, sender=k4))
                self.raiseOnZeroStatus(txid)

        return

        if ERC20:
            self.rc0.functions.submitAnswerForERC20(self.question_id, to_answer_for_contract(12345), 0, k5, 100).transact(self._txargs(sender=k4))
        else:
            self.rc0.functions.submitAnswerFor(self.question_id, to_answer_for_contract(12345), 0, k5).transact(self._txargs(val=100, sender=k4))

        self._advance_clock(33)
        self.rc0.functions.claimWinnings(self.question_id, [decode_hex("0x00")], [k5], [100], [to_answer_for_contract(12345)]).transact(self._txargs(sender=k5))

        starting_deposited = self.rc0.functions.balanceOf(k5).call()
        self.assertEqual(starting_deposited, 1100)

        gas_used = 0

        if ERC20:
            starting_bal = self.l2token0.functions.balanceOf(k5).call()
        else:
            starting_bal = self.l2web3.eth.get_balance(k5)

        txid = self.rc0.functions.withdraw().transact(self._txargs(sender=k5))
        rcpt = self.l2web3.eth.get_transaction_receipt(txid)
        gas_used = rcpt['cumulativeGasUsed']

        if ERC20:
            ending_bal = self.l2token0.functions.balanceOf(k5).call()
        else:
            ending_bal = self.l2web3.eth.get_balance(k5)

        self.assertEqual(self.rc0.functions.balanceOf(k5).call(), 0)

        if ERC20:
            self.assertEqual(ending_bal, starting_bal + starting_deposited)
        else:
            self.assertEqual(ending_bal, starting_bal + starting_deposited - gas_used)

        return


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_fee_received(self):
        self.assertEqual(self.rc0.functions.balanceOf(self.arb0.address).call(), 100)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_non_erc_ask_question_id(self):

        # ERC20 also supports a plain askQuestion without a bounty
        expected_question_id = calculate_question_id(self.rc0.address, 0, "my question x", self.arb0.address, 30, 0, 0, self.l2web3.eth.accounts[0], 0)

        # Non-ERC version only has one method which is already tested elsewhere
        if not ERC20:
            return

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        # There's a question fee so this should fail
        with self.assertRaises(TransactionFailed):
            txid = self.rc0.functions.askQuestion(
                0,
                "my question x",
                self.arb0.address,
                30,
                0,
                0
            ).transact(self._txargs())
            self.raiseOnZeroStatus(txid)

        self.assertEqual(self.rc0.functions.questions(expected_question_id).call()[QINDEX_ARBITRATOR], NULL_ADDRESS)

        self.arb0.functions.setQuestionFee(0).transact()

        txid = self.rc0.functions.askQuestion(
            0,
            "my question x",
            self.arb0.address,
            30,
            0,
            0
        ).transact(self._txargs())
        self.raiseOnZeroStatus(txid)
        self.assertNotEqual(self.rc0.functions.questions(expected_question_id).call()[QINDEX_ARBITRATOR], NULL_ADDRESS, "We have a question at the expected address")

        
    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_ask_question_gas(self):

        if ERC20:
            txid = self.rc0.functions.askQuestionERC20(
                0,
                "my question 2",
                self.arb0.address,
                10,
                0,
                0
                ,1100
            ).transact()
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            gas_used = rcpt['cumulativeGasUsed']
            self.assertTrue(gas_used < 140000)
        else:
            txid = self.rc0.functions.askQuestion(
                0,
                "my question 2",
                self.arb0.address,
                10,
                0,
                0
            ).transact(self._txargs(val=1100))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            gas_used = rcpt['cumulativeGasUsed']
            #self.assertEqual(gas_used, 120000)
            self.assertTrue(gas_used < 110000)
    
    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_answer_question_gas(self):

        if ERC20:

            txid = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12345), 0
            ,1
            ).transact()
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)

            self.assertTrue(rcpt['cumulativeGasUsed'] < 140000)

            # NB The second answer should be cheaper than the first.
            # This is what we want, because you may need to be able to get a challenge through at busy times

            txid2 = self.rc0.functions.submitAnswerERC20(self.question_id, to_answer_for_contract(12346), 0
            ,2
            ).transact()
            rcpt = self.l2web3.eth.get_transaction_receipt(txid2)
            self.assertTrue(rcpt['cumulativeGasUsed'] < 80000)

        else:

            txid = self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)

            self.assertTrue(rcpt['cumulativeGasUsed'] < 103000)

            # NB The second answer should be cheaper than the first.
            # This is what we want, because you may need to be able to get a challenge through at busy times

            txid2 = self.rc0.functions.submitAnswer(self.question_id, to_answer_for_contract(12346), 0).transact(self._txargs(val=2)) 
            rcpt = self.l2web3.eth.get_transaction_receipt(txid2)
            self.assertTrue(rcpt['cumulativeGasUsed'] < 56000)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_question_fee_withdrawal(self):

        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k7 = self.l2web3.eth.accounts[7]

        if ERC20:
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k7, 1000000, 1000000)

        start_bal = self.rc0.functions.balanceOf(self.arb0.address).call()
        self.arb0.functions.setQuestionFee(321).transact()


        if ERC20:

            txid = self.rc0.functions.askQuestionERC20(
                0,
                "my question 3",
                self.arb0.address,
                10,
                0,
                0
                ,1000
            ).transact(self._txargs(sender=k4))

            txid = self.rc0.functions.askQuestionERC20(
                0,
                "my question 4",
                self.arb0.address,
                10,
                0,
                0
                ,2000
            ).transact(self._txargs(sender=k5))

            end_bal = self.rc0.functions.balanceOf(self.arb0.address).call()
            self.assertEqual(end_bal - start_bal, (321*2))

            start_arb_bal = self.l2token0.functions.balanceOf(self.arb0.address).call()
            txid = self.arb0.functions.callWithdraw().transact(self._txargs(sender=k7))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            end_arb_bal = self.l2token0.functions.balanceOf(self.arb0.address).call()

            self.assertEqual(end_arb_bal - start_arb_bal, 100 + (321*2))
            self.assertEqual(self.rc0.functions.balanceOf(self.arb0.address).call(), 0)

        else:

            question_id = self.rc0.functions.askQuestion(
                0,
                "my question 3",
                self.arb0.address,
                10,
                0,
                0
            ).transact(self._txargs(val=1000, sender=k4))

            question_id = self.rc0.functions.askQuestion(
                0,
                "my question 4",
                self.arb0.address,
                10,
                0,
                0
            ).transact(self._txargs(val=2000, sender=k5))

            end_bal = self.rc0.functions.balanceOf(self.arb0.address).call()
            self.assertEqual(end_bal - start_bal, (321*2))

            start_arb_bal = self.l2web3.eth.get_balance(self.arb0.address)
            txid = self.arb0.functions.callWithdraw().transact(self._txargs(sender=k7))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            end_arb_bal = self.l2web3.eth.get_balance(self.arb0.address)

        self.assertEqual(end_arb_bal - start_arb_bal, 100 + (321*2))
        self.assertEqual(self.rc0.functions.balanceOf(self.arb0.address).call(), 0)


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_question_fees(self):

        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]

        if ERC20:
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)

        # Treat k5 as the arbitrator for these purposes, although really the arbitrator would be a contract
        self.rc0.functions.setQuestionFee(123).transact(self._txargs(sender=k5))

        if ERC20:
            # Should fail with insufficient payment to cover the question fee
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.askQuestionERC20(
                    0,
                    "my question 2",
                    k5,
                    10,
                    0,
                    0
                    ,122
                ).transact( self._txargs(sender=k4))
                self.raiseOnZeroStatus(txid)

            txid = self.rc0.functions.askQuestionERC20(
                0,
                "my question 2",
                k5,
                10,
                0,
                0
                ,126
            ).transact(self._txargs(sender=k4))

        else:

            # Should fail with insufficient payment to cover the question fee
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.askQuestion(
                    0,
                    "my question 2",
                    k5,
                    10,
                    0,
                    0
                ).transact( self._txargs(val=122, sender=k4))
                self.raiseOnZeroStatus(txid)

            txid = self.rc0.functions.askQuestion(
                0,
                "my question 2",
                k5,
                10,
                0,
                0
            ).transact(self._txargs(val=126, sender=k4))

        question_id = calculate_question_id(self.rc0.address, 0, "my question 2", k5, 10, 0, 0, k4, 0)

        bounty = self.rc0.functions.questions(question_id).call()[QINDEX_BOUNTY]
        self.assertEqual(bounty, 126-123, "The bounty is what's left after the question fee is deducted")

        if ERC20:
            question_id = self.rc0.functions.askQuestionERC20(
                0,
                "my question 3",
                k5,
                10,
                0,
                0
                ,122
            ).transact(self._txargs(sender=k5))
        else:
            question_id = self.rc0.functions.askQuestion(
                0,
                "my question 3",
                k5,
                10,
                0,
                0
            ).transact(self._txargs(val=122, sender=k5))


        question_id = calculate_question_id(self.rc0.address, 0, "my question 3", k5, 10, 0, 0, k5, 0)

        bounty = self.rc0.functions.questions(question_id).call()[QINDEX_BOUNTY]
        self.assertEqual(bounty, 122, "The arbitrator isn't charged their fee, so their whole payment goes to the bounty")

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_minimum_bond(self):

        if VERNUM < 3:
            print("Skipping askQuestionWithMinBond, not a feature of this contract")
            return

        k0 = self.l2web3.eth.accounts[0]

        if ERC20:
            bal_before_in_contract = self.rc0.functions.balanceOf(k0).call()
            self.assertEqual(bal_before_in_contract, 0, "nothing in the contract at the start")
            bal_before = self.l2token0.functions.balanceOf(k0).call()
            txid = self.rc0.functions.askQuestionWithMinBondERC20(
                0,
                "my question 2",
                self.arb0.address,
                10,
                0,
                0,
                1000,
                1100
            ).transact(self._txargs())
            bal_after = self.l2token0.functions.balanceOf(k0).call()
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            self.assertEqual(bal_after, bal_before - 1100, "New question bounty is deducted")
            gas_used = rcpt['cumulativeGasUsed']
        else:
            bal_before = self.l2web3.eth.get_balance(k0)
            txid = self.rc0.functions.askQuestionWithMinBond(
                0,
                "my question 2",
                self.arb0.address,
                10,
                0,
                0,
                1000
            ).transact(self._txargs(val=1100))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            gas_used = rcpt['cumulativeGasUsed']
            bal_after = self.l2web3.eth.get_balance(k0)
            self.assertEqual(bal_after, bal_before - 1100 - gas_used, "New question bouny is deducted")

        #self.assertEqual(gas_used, 120000)
        self.assertTrue(gas_used < 160000)

        expected_question_id = calculate_question_id(self.rc0.address, 0, "my question 2", self.arb0.address, 10, 0, 0, self.l2web3.eth.accounts[0], 1000)

        min_bond = self.rc0.functions.questions(expected_question_id).call()[QINDEX_MIN_BOND]
        self.assertEqual(min_bond, 1000)

        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.submitAnswerERC20(expected_question_id, to_answer_for_contract(123), 0, 0).transact(self._txargs())
            else:
                txid = self.rc0.functions.submitAnswer(expected_question_id, to_answer_for_contract(123), 0).transact(self._txargs(val=0))
            self.raiseOnZeroStatus(txid)

        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.submitAnswerERC20(expected_question_id, to_answer_for_contract(1234), 0, 999).transact(self._txargs())
            else:
                txid = self.rc0.functions.submitAnswer(expected_question_id, to_answer_for_contract(1234), 0).transact(self._txargs(val=999))
            self.raiseOnZeroStatus(txid)

        if ERC20:
            txid = self.rc0.functions.submitAnswerERC20(expected_question_id, to_answer_for_contract(12345), 0, 1000).transact(self._txargs())
        else:
            txid = self.rc0.functions.submitAnswer(expected_question_id, to_answer_for_contract(12345), 0).transact(self._txargs(val=1000))
        self.raiseOnZeroStatus(txid)

        best_answer = self.rc0.functions.questions(expected_question_id).call()[QINDEX_BEST_ANSWER]
        self.assertEqual(12345, from_answer_for_contract(best_answer))

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_metadata(self):

        k0 = self.l2web3.eth.accounts[0]
        k1 = self.l2web3.eth.accounts[1]

        self.assertEqual(self.arb0.functions.metadata().call(), '')

        with self.assertRaises(TransactionFailed):
            txid = self.arb0.functions.setMetaData("oink").transact(self._txargs(sender=k1))
            self.raiseOnZeroStatus(txid)

        self.arb0.functions.setMetaData("oink").transact(self._txargs(sender=k0))
        self.assertEqual(self.arb0.functions.metadata().call(), 'oink')


    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_arbitrator_registered_wallet(self):

        k2 = self.l2web3.eth.accounts[2]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        k7 = self.l2web3.eth.accounts[7]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)
            self._issueTokens(self.l2token1, k5, 1000000, 1000000)
            self._issueTokens(self.l2token1, k7, 1000000, 1000000)

        start_bal = self.rc0.functions.balanceOf(self.arb0.address).call()
        self.arb0.functions.setQuestionFee(321).transact()

        if ERC20:
            question_id = self.rc0.functions.askQuestionERC20(
                0,
                "my question 3",
                self.arb0.address,
                10,
                0,
                0
                ,1000
            ).transact(self._txargs(sender=k4))

            question_id = self.rc0.functions.askQuestionERC20(
                0,
                "my question 4",
                self.arb0.address,
                10,
                0,
                0
                ,2000
            ).transact(self._txargs(sender=k5))

        else:
            question_id = self.rc0.functions.askQuestion(
                0,
                "my question 3",
                self.arb0.address,
                10,
                0,
                0
            ).transact(self._txargs(val=1000, sender=k4))

            question_id = self.rc0.functions.askQuestion(
                0,
                "my question 4",
                self.arb0.address,
                10,
                0,
                0
            ).transact(self._txargs(val=2000, sender=k5))

        end_bal = self.rc0.functions.balanceOf(self.arb0.address).call()
        self.assertEqual(end_bal - start_bal, (321*2))

        with self.assertRaises(TransactionFailed):
            txid = self.arb0.functions.withdrawToRegisteredWallet().transact()
            self.raiseOnZeroStatus(txid)

        with self.assertRaises(TransactionFailed):
            txid = self.arb0.functions.updateRegisteredWallet(t.a8).transact(self._txargs(sender=k2))
            self.raiseOnZeroStatus(txid)
        
        self.arb0.functions.updateRegisteredWallet(t.a8).transact()

        if ERC20:
            # Skip this for now as we're not actually using the RegisteredWallet
            return

        if ERC20:
            start_arb_bal = self.l2token0.functions.balanceOf(t.a8).call()
        else:
            start_arb_bal = self.l2web3.eth.get_balance(t.a8)

        self.arb0.functions.callWithdraw().transact(self._txargs(sender=k7))
        self.arb0.functions.withdrawToRegisteredWallet().transact(self._txargs(sender=k4))

        if ERC20:
            end_arb_bal = self.l2token0.functions.balanceOf(t.a8).call()
        else:
            end_arb_bal = self.l2web3.eth.get_balance(t.a8)

        self.assertEqual(end_arb_bal - start_arb_bal, (100+321+321))
        self.assertEqual(self.rc0.functions.balanceOf(self.arb0.address).call(), 0)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_null_arbitrator_permitted(self):

        if VERNUM < 3:
            return

        NULL_ADDRESS = "0x0000000000000000000000000000000000000000"

        k2 = self.l2web3.eth.accounts[2]

        if ERC20:
            self._issueTokens(self.l2token1, k2, 1000000, 1000000)
            txid = self.rc0.functions.askQuestionERC20(
                0,
                "my question 3",
                NULL_ADDRESS,
                10,
                0,
                0,
                1000
            ).transact(self._txargs(sender=k2))
        else:
            txid = self.rc0.functions.askQuestion(
                0,
                "my question 3",
                NULL_ADDRESS,
                10,
                0,
                0
            ).transact(self._txargs(val=1000, sender=k2))
        self.raiseOnZeroStatus(txid)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_reopen_question(self):

        if VERNUM < 3.0:
            print("Skipping test_reopen_question, not a feature of this contract")
            return

        k0 = self.l2web3.eth.accounts[0]
        if ERC20:
            self._issueTokens(self.l2token1, k0, 1000000, 1000000)

        if ERC20:
            txid = self.rc0.functions.submitAnswerERC20(self.question_id, ANSWERED_TOO_SOON_VAL, 0, 3).transact() 
        else:
            txid = self.rc0.functions.submitAnswer(self.question_id, ANSWERED_TOO_SOON_VAL, 0).transact(self._txargs(val=3)) 
            self.raiseOnZeroStatus(txid)

        self._advance_clock(33)

        self.assertEqual(encode_hex(self.rc0.functions.resultFor(self.question_id).call()), ANSWERED_TOO_SOON_VAL)
        self.assertTrue(self.rc0.functions.isSettledTooSoon(self.question_id).call())

        with self.assertRaises(TransactionFailed):
            self.rc0.functions.resultForOnceSettled(self.question_id).call()

        self.assertEqual(self.rc0.functions.balanceOf(k0).call(), 0)
        self.rc0.functions.claimWinnings(self.question_id, [decode_hex("0x00")], [k0], [3], [ANSWERED_TOO_SOON_VAL]).transact()
        self.assertEqual(self.rc0.functions.balanceOf(k0).call(), 3, "Winner gets their bond back but no bounty")

        self.assertEqual(self.rc0.functions.reopened_questions(self.question_id).call(), to_answer_for_contract(0), "reopened_questions empty until reopened")

        old_bounty = self.rc0.functions.questions(self.question_id).call()[QINDEX_BOUNTY]
        self.assertEqual(old_bounty, 1000)

        # Make one of the details different to the original question and it should fail
        if ERC20:
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.reopenQuestionERC20( 0, "not my question", self.arb0.address, 30, 0, 1, 0, self.question_id, 123).transact(self._txargs())
                self.raiseOnZeroStatus(txid)
        else:
            with self.assertRaises(TransactionFailed):
                txid = self.rc0.functions.reopenQuestion( 0, "not my question", self.arb0.address, 30, 0, 1, 0, self.question_id).transact(self._txargs(val=123))
                self.raiseOnZeroStatus(txid)

        expected_reopen_id = calculate_question_id(self.rc0.address, 0, "my question", self.arb0.address, 30, 0, 1, self.l2web3.eth.accounts[0], 0)

        if ERC20:
            # withdraw anything we have in contract balance as it complicates the test
            self.rc0.functions.withdraw().transact(self._txargs())
            bal_before = self.l2token0.functions.balanceOf(k0).call()
            txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 1, 0, self.question_id, 123).transact(self._txargs(gas=300000))
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            self.raiseOnZeroStatus(txid)
            bal_after = self.l2token0.functions.balanceOf(k0).call()
            self.assertEqual(bal_after, bal_before - 123, "New question bounty is deducted")
        else:
            bal_before = self.l2web3.eth.get_balance(k0)
            txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 1, 0, self.question_id).transact(self._txargs(val=123))
            self.raiseOnZeroStatus(txid)
            rcpt = self.l2web3.eth.get_transaction_receipt(txid)
            gas_spent = rcpt['cumulativeGasUsed']
            bal_after = self.l2web3.eth.get_balance(k0)
            self.assertEqual(bal_after, bal_before - 123 - gas_spent, "New question bounty is deducted")
        txr = self.l2web3.eth.get_transaction_receipt(txid)

        self.assertEqual(self.rc0.functions.reopened_questions(self.question_id).call(), expected_reopen_id, "reopened_questions returns reopened question id")

        old_bounty_now = self.rc0.functions.questions(self.question_id).call()[QINDEX_BOUNTY]
        self.assertEqual(old_bounty_now, 0)

        new_bounty = self.rc0.functions.questions(expected_reopen_id).call()[QINDEX_BOUNTY]
        question_fee = 100
        self.assertEqual(new_bounty, old_bounty + 123 - question_fee)

        # Second time should fail
        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 1, 0, self.question_id, 123).transact(self._txargs())
            else:
                txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 1, 0, self.question_id).transact(self._txargs(val=123))

            self.raiseOnZeroStatus(txid)

        # Different nonce should still fail
        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 2, 0, self.question_id, 123).transact(self._txargs(val=123))
            else:
                txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 2, 0, self.question_id).transact(self._txargs(val=123))
            self.raiseOnZeroStatus(txid)

        if ERC20:
            self.rc0.functions.submitAnswerERC20(expected_reopen_id, ANSWERED_TOO_SOON_VAL, 0, 3).transact(self._txargs()) 
        else:
            self.rc0.functions.submitAnswer(expected_reopen_id, ANSWERED_TOO_SOON_VAL, 0).transact(self._txargs(val=3)) 
        self._advance_clock(33)
        self.assertEqual(self.rc0.functions.getFinalAnswer(expected_reopen_id).call(), ANSWERED_TOO_SOON_VAL)

        # If the question is a reopen, it can't itself be reopened until the previous question has been reopened
        # This prevents to bounty from being moved to a child before it can be returned to the new replacement of the original question.
        expected_reopen_id_b = calculate_question_id(self.rc0.address, 0, "my question", self.arb0.address, 30, 0, 4, self.l2web3.eth.accounts[0], 0)
        with self.assertRaises(TransactionFailed):
            if ERC20:
                txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 4, 0, expected_reopen_id, 123).transact(self._txargs())
            else:
                txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 4, 0, expected_reopen_id).transact(self._txargs(val=123))
            self.raiseOnZeroStatus(txid)

        pre_reopen_bounty = self.rc0.functions.questions(expected_reopen_id).call()[QINDEX_BOUNTY]

        expected_reopen_id_2 = calculate_question_id(self.rc0.address, 0, "my question", self.arb0.address, 30, 0, 2, self.l2web3.eth.accounts[0], 0)

        if ERC20:
            txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 2, 0, self.question_id, 543).transact(self._txargs())
        else:
            txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 2, 0, self.question_id).transact(self._txargs(val=543))

        self.raiseOnZeroStatus(txid)

        post_reopen_bounty = self.rc0.functions.questions(expected_reopen_id).call()[QINDEX_BOUNTY]
        self.assertEqual(post_reopen_bounty, 0, "reopening a question moves the bounty from the reopened question to the new question")

        post_reopen_bounty_b = self.rc0.functions.questions(expected_reopen_id_2).call()[QINDEX_BOUNTY]
        self.assertEqual(post_reopen_bounty_b, pre_reopen_bounty + 543 - question_fee)

        self.assertEqual(self.rc0.functions.reopened_questions(self.question_id).call(), expected_reopen_id_2, "reopened_questions returns now new question id")

        # Now you've reopened the parent you can reopen the child if you like, although this is usually a bad idea because you should be using the parent
        if ERC20:
            txid = self.rc0.functions.reopenQuestionERC20( 0, "my question", self.arb0.address, 30, 0, 4, 0, expected_reopen_id, 123).transact(self._txargs())
        else:
            txid = self.rc0.functions.reopenQuestion( 0, "my question", self.arb0.address, 30, 0, 4, 0, expected_reopen_id).transact(self._txargs(val=123))
        self.raiseOnZeroStatus(txid)

        if ERC20:
            self.rc0.functions.submitAnswerERC20(expected_reopen_id_2, to_answer_for_contract(432), 0, 3).transact(self._txargs()) 
        else:
            self.rc0.functions.submitAnswer(expected_reopen_id_2, to_answer_for_contract(432), 0).transact(self._txargs(val=3)) 

        self._advance_clock(33)
        self.assertEqual(from_answer_for_contract(self.rc0.functions.getFinalAnswer(expected_reopen_id_2).call()), 432)
        self.assertFalse(self.rc0.functions.isSettledTooSoon(expected_reopen_id_2).call())

        self.assertEqual(from_answer_for_contract(self.rc0.functions.resultForOnceSettled(self.question_id).call()), 432)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_too_soon_bounty(self):

        if VERNUM < 3.0:
            print("Skipping test_reopen_question, not a feature of this contract")
            return

        k0 = self.l2web3.eth.accounts[0]
        k3 = self.l2web3.eth.accounts[3]
        k5 = self.l2web3.eth.accounts[5]
        if ERC20:
            self._issueTokens(self.l2token1, k0, 1000000, 1000000)
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 2, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 2, 4, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 4, 8, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 8, 16, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 16, 32, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, ANSWERED_TOO_SOON_VAL, 32, 64, k3)
        claimable = 64+32+16+8+4+2 # no 1000, which was the original bounty

        self._advance_clock(33)

        self.assertEqual(self.rc0.functions.getFinalAnswer(self.question_id).call(), ANSWERED_TOO_SOON_VAL)
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 0)

        # Have an unconnected user do the claim
        # This will leave the balance in the contract rather than withdrawing it
        self.rc0.functions.claimMultipleAndWithdrawBalance([self.question_id], [len(st['hash'])], st['hash'], st['addr'], st['bond'], st['answer']).transact(self._txargs(sender=k5))
        
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), claimable)

    @unittest.skipIf(WORKING_ONLY, "Not under construction")
    def test_too_soon_bonds_under_unrevealed_commit(self):

        if VERNUM < 3.0:
            print("Skipping test_reopen_question, not a feature of this contract")
            return

        k0 = self.l2web3.eth.accounts[0]
        k3 = self.l2web3.eth.accounts[3]
        k4 = self.l2web3.eth.accounts[4]
        k5 = self.l2web3.eth.accounts[5]
        if ERC20:
            self._issueTokens(self.l2token1, k0, 1000000, 1000000)
            self._issueTokens(self.l2token1, k3, 1000000, 1000000)
            self._issueTokens(self.l2token1, k4, 1000000, 1000000)

        st = None
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 0, 200, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 200, 400, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 400, 800, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 800, 1600, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 1600, 3200, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, ANSWERED_TOO_SOON_VAL, 3200, 6400, k3)
        st = self.submitAnswerReturnUpdatedState( st, self.question_id, 1001, 6400, 12800, k4, True) # We'll submit this but not reveal it
        claimable = 12800+subfee(6400)+subfee(3200)+subfee(1600)+subfee(800)+subfee(400)+subfee(200) # no 1000, which was the original bounty

        self._advance_clock(33)

        self.assertEqual(self.rc0.functions.getFinalAnswer(self.question_id).call(), ANSWERED_TOO_SOON_VAL)
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), 0)

        # Have an unconnected user do the claim
        # This will leave the balance in the contract rather than withdrawing it
        self.rc0.functions.claimMultipleAndWithdrawBalance([self.question_id], [len(st['hash'])], st['hash'], st['addr'], st['bond'], st['answer']).transact(self._txargs(sender=k5))
        
        self.assertEqual(self.rc0.functions.balanceOf(k3).call(), claimable)


 






if __name__ == '__main__':
    main()


