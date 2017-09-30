from unittest import TestCase, main
from rlp.utils import encode_hex, decode_hex
from ethereum.tools import tester as t
from ethereum.tools.tester import TransactionFailed
from ethereum.tools import keys
from sha3 import keccak_256 as sha3_256
import math
from ethereum.pow.ethpow import Miner 

class TestRealityToken(TestCase):

    # Mostly copied from pyethereums tools/tester.py
    # Basically the same except allows us to specify how many seconds to advance
    # TODO: Work out the correct way to do this, or patch pyethereum if there isn't one
    def mine(self, number_of_blocks=1, coinbase=None, secs = 14):
        c = self.c
        timestamp = c.chain.state.timestamp + secs
        if coinbase is None:
            coinbase = t.a0
        c.cs.finalize(c.head_state, c.block)
        t.set_execution_results(c.head_state, c.block)
        c.block = Miner(c.block).mine(rounds=100, start_nonce=0)
        assert c.chain.add_block(c.block)
        assert c.head_state.trie.root_hash == c.chain.state.trie.root_hash
        for i in range(1, number_of_blocks+1):
            b, _ = t.make_head_candidate(c.chain, timestamp=timestamp + 14)
            b = Miner(b).mine(rounds=100, start_nonce=0)
        assert c.chain.add_block(b)
        c.block = t.mk_block_from_prevstate(c.chain, timestamp=timestamp + 14)
        c.head_state = c.chain.state.ephemeral_clone()
        c.cs.initialize(c.head_state, c.block)

    def setUp(self):

        self.c = t.Chain()
        self.s = self.c.head_state

        rc_code = open('RealityToken.sol').read()
        self.rc = self.c.contract(rc_code, language='solidity', sender=t.k0)

        window_branches = self.rc.getWindowBranches(0)
        genesis_branch_hash = self.rc.window_branches(0, 0)
        #print encode_hex(genesis_branch_hash)
        self.assertEqual(len(genesis_branch_hash), 32)


    def test_register_and_fetch(self):

        # a
        # aa             ab
        # aaa  aab       aba
        # aaaa aaba aabb abaa
        #self.c.mine()
        #self.s = self.c.head_state

        genesis_hash = decode_hex("fca5e1a248b8fee34db137da5e38b41f95d11feb5a8fa192a150d8d5d8de1c59")

        null_hash = decode_hex("0000000000000000000000000000000000000000000000000000000000000000")
        # print encode_hex(null_hash)

        k0_addr = encode_hex(keys.privtoaddr(t.k0))
        k1_addr = encode_hex(keys.privtoaddr(t.k1))
        k2_addr = encode_hex(keys.privtoaddr(t.k2))

        contract_addr = encode_hex(keys.privtoaddr(t.k9))

        self.assertEqual(k1_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')

        self.assertEqual(self.rc.balanceOf(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)


        self.rc.transfer(k1_addr, 1000000, genesis_hash, sender=t.k0)

        # self.s.timestamp = self.s.timestamp + 100
        # self.s = t.state()

        # print self.s.gas_used - u
        u = self.s.gas_used
        # print self.s.get_balance(k0_addr)

        window_index = 4 # index of genesis hash in struct

        self.assertEqual(self.rc.balanceOf(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.rc.balanceOf(k1_addr, genesis_hash), 1000000)

        genesis_branch = self.rc.branches(genesis_hash);
        self.assertEqual(null_hash, genesis_branch[0])
        self.assertEqual(0, genesis_branch[window_index], "Genesis hash window is 0")

        madeup_block_hash = decode_hex(sha3_256('pants').hexdigest())

        dummy_merkle_root_aa = decode_hex(sha3_256('aa').hexdigest())
        dummy_merkle_root_ab = decode_hex(sha3_256('ab').hexdigest())

        dummy_merkle_root_aab = decode_hex(sha3_256('aab').hexdigest())
        dummy_merkle_root_aba = decode_hex(sha3_256('aba').hexdigest())
        dummy_merkle_root_abb = decode_hex(sha3_256('abb').hexdigest())

        dummy_merkle_root_aaaa = decode_hex(sha3_256('aaaa').hexdigest())
        dummy_merkle_root_aaba = decode_hex(sha3_256('aaba').hexdigest())
        dummy_merkle_root_abaa = decode_hex(sha3_256('abaa').hexdigest())

        failed = False
        try:
            branch_aa_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_aa, contract_addr, startgas=200000)
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, "You can't build on a block in the window in which it was created")

        self.mine(secs=86400)

        branch_aa_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_aa, contract_addr)

        self.assertEqual(1, len(self.rc.getWindowBranches(1)))
        self.assertEqual([branch_aa_hash], self.rc.getWindowBranches(1))

        aa_branch = self.rc.branches(branch_aa_hash);
        self.assertEqual(1, aa_branch[window_index], "First branch window is 1")

        self.mine(secs=86400*4)

        branch_ab_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_ab, contract_addr)

        ab_branch = self.rc.branches(branch_ab_hash);
        self.assertEqual(5, ab_branch[window_index])
        self.assertEqual(5, ab_branch[window_index], "window of branch created a few days later is 5, despite having skipped several days")

        self.mine(secs=86400)

        # print encode_hex(self.rc.branches(branch_ab_hash)[0])

        branch_aab_hash = self.rc.createBranch(branch_aa_hash, dummy_merkle_root_aab, contract_addr)
        branch_aba_hash = self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba, contract_addr)
        self.assertEqual(2, len(self.rc.getWindowBranches(6)))
        self.assertEqual([branch_aab_hash, branch_aba_hash], self.rc.getWindowBranches(6))

        self.mine(secs=86400)

        null_test_merkle_root = decode_hex(sha3_256('nulltest').hexdigest())

        failed = False
        try:
            self.rc.createBranch(null_hash, null_test_merkle_root, contract_addr, startgas=200000)
            self.c.mine()
        except TransactionFailed:
            failed = True 
        self.assertTrue(failed, "You cannot create a branch with a null parent hash")

        self.assertEqual(self.rc.balanceOf(k1_addr, branch_aa_hash), 1000000)

        self.assertTrue(self.rc.isAmountSpendable(k1_addr, 1000000, branch_aa_hash))
        self.assertTrue(self.rc.isAmountSpendable(k1_addr, 1, branch_ab_hash))
        self.assertFalse(self.rc.isAmountSpendable(k1_addr, 1000001, branch_ab_hash))

        failed = False
        try:
            self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba, contract_addr, startgas=200000)
            self.c.mine()
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, "You can only create a branch with a given hash once")

        #print "Gas used to send coins after %d blocks: %d" % (2, self.s.gas_used - u)
        self.rc.transfer(k2_addr, 500000, branch_aa_hash, sender=t.k1)
        #print "Gas used to send coins after %d blocks: %d" % (2, self.s.block.gas_used - u)

        self.assertEqual(self.rc.balanceOf(k2_addr, branch_aa_hash), 500000)
        self.assertEqual(self.rc.balanceOf(k2_addr, branch_ab_hash), 0)

        branch_hash = branch_aba_hash
        for i in range(0,10):
            dummy_merkle_root = decode_hex(sha3_256('dummy' + str(i)).hexdigest())
            branch_hash = self.rc.createBranch(branch_hash, dummy_merkle_root, contract_addr)
            self.mine(secs=86400)
            # print encode_hex(branch_hash)

        u = self.c.block.gas_used
        self.rc.transfer(k2_addr, 500000, branch_hash, sender=t.k1)

        gas_used = self.c.block.gas_used - u
        #print "Gas used to send coins after %d blocks: %d" % (i+1, gas_used)
        # self.assertTrue(u < 130000, "100 branches read in less than 130000 gas")

        failed = False
        try:
            self.rc.transfer(k2_addr, 1, branch_aba_hash, sender=t.k1)
        except:
            failed = True


        k0_bal = self.rc.balanceOf(k0_addr, branch_ab_hash)
        #print k0_bal
        self.rc.transfer(k2_addr, 5, branch_aba_hash, sender=t.k0)
        branch_abaa_hash = self.rc.createBranch(branch_aba_hash, dummy_merkle_root_abaa, contract_addr)
        self.mine(secs=86400)
        k0_bal_spent = self.rc.balanceOf(k0_addr, branch_abaa_hash)

        #print k0_bal_spent
        self.assertEqual(k0_bal_spent, k0_bal - 5)

        self.assertFalse(self.rc.transfer(k2_addr, 5, branch_ab_hash, sender=t.k0), "Attempting to send coins on an earlier branch returns false")
        self.assertEqual(k0_bal_spent, k0_bal - 5, "Attempt to send coins on an earlier branch left balance unchanged")
        return


    def test_allowances(self):

        # a
        # aa             ab
        # aaa  aab       aba
        # aaaa aaba aabb abaa

        genesis_hash = decode_hex("fca5e1a248b8fee34db137da5e38b41f95d11feb5a8fa192a150d8d5d8de1c59")

        null_hash = decode_hex("0000000000000000000000000000000000000000000000000000000000000000")
        # print encode_hex(null_hash)

        k0_addr = encode_hex(keys.privtoaddr(t.k0))
        k1_addr = encode_hex(keys.privtoaddr(t.k1))
        k2_addr = encode_hex(keys.privtoaddr(t.k2))

        contract_addr = encode_hex(keys.privtoaddr(t.k9))

        self.assertEqual(k1_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')

        self.assertEqual(self.rc.balanceOf(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        self.rc.transfer(k1_addr, 1000000, genesis_hash, sender=t.k0, startgas=200000)

        # self.s.block.timestamp = self.s.block.timestamp + 100
        # self.s = t.state()

        window_index = 4 # index of genesis hash in struct

        self.assertEqual(self.rc.balanceOf(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.rc.balanceOf(k1_addr, genesis_hash), 1000000)

        with self.assertRaises(TransactionFailed):
            self.rc.transferFrom(k0_addr, k1_addr, 400000, genesis_hash, sender=t.k2, startgas=200000)

        self.rc.approve(k2_addr, 500000, genesis_hash, sender=t.k0, startgas=200000)

        with self.assertRaises(TransactionFailed):
            self.rc.transferFrom(k0_addr, k1_addr, 600000, genesis_hash, sender=t.k2, startgas=200000)

        start_bal = self.rc.balanceOf(k0_addr, genesis_hash)

        self.rc.transferFrom(k0_addr, k1_addr, 400000, genesis_hash, sender=t.k2, startgas=200000)
        #self.assertEqual(self.rc.balanceOf(k1_addr, genesis_hash), 1000000-500000)

        self.mine()

        self.assertEqual(self.rc.balanceOf(k1_addr, genesis_hash), 400000+1000000)
        self.assertEqual(self.rc.balanceOf(k0_addr, genesis_hash), start_bal - 400000)

        with self.assertRaises(TransactionFailed):
            self.rc.transferFrom(k0_addr, 400000, genesis_hash, sender=t.k2, startgas=200000)

if __name__ == '__main__':
    main()
