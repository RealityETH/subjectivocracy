from unittest import TestCase, main
from rlp.utils import encode_hex, decode_hex
from ethereum import tester as t
from ethereum.tester import TransactionFailed
from ethereum import keys
import time
from sha3 import sha3_256


class TestRealityToken(TestCase):

    def setUp(self):

        self.s = t.state()
        rc_code = open('realitytoken.sol').read()
        self.rc = self.s.abi_contract(rc_code, language='solidity', sender=t.k0)
        # print encode_hex(genesis_branch_hash)

    def test_register_and_fetch(self):

        # a
        # aa             ab
        # aaa  aab       aba
        # aaaa aaba aabb abaa

        genesis_hash = decode_hex("01bd7e296e8be10ff0f93bf1b7186d884f05bdc2c293dbc4ca3ea18a5f7c9ebd")
        null_hash = decode_hex("0000000000000000000000000000000000000000000000000000000000000000")
        # print encode_hex(null_hash)

        k0_addr = encode_hex(keys.privtoaddr(t.k0))
        k1_addr = encode_hex(keys.privtoaddr(t.k1))
        k2_addr = encode_hex(keys.privtoaddr(t.k2))

        self.assertEqual(k1_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')
        self.assertEqual(self.rc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        u = self.s.block.gas_used

        self.rc.sendCoin(k1_addr, 1000000, genesis_hash, sender=t.k0)

        # self.s.block.timestamp = self.s.block.timestamp + 100
        # self.s = t.state()

        # print self.s.block.gas_used - u
        u = self.s.block.gas_used
        # print self.s.block.get_balance(k0_addr)

        self.assertEqual(self.rc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.rc.getBalance(k1_addr, genesis_hash), 1000000)

        madeup_block_hash = decode_hex(sha3_256('pants').hexdigest())

        dummy_merkle_root_aa = decode_hex(sha3_256('aa').hexdigest())
        dummy_merkle_root_ab = decode_hex(sha3_256('ab').hexdigest())

        dummy_merkle_root_aab = decode_hex(sha3_256('aab').hexdigest())
        dummy_merkle_root_aba = decode_hex(sha3_256('aba').hexdigest())
        dummy_merkle_root_abb = decode_hex(sha3_256('abb').hexdigest())

        dummy_merkle_root_aaaa = decode_hex(sha3_256('aaaa').hexdigest())
        dummy_merkle_root_aaba = decode_hex(sha3_256('aaba').hexdigest())
        dummy_merkle_root_abaa = decode_hex(sha3_256('abaa').hexdigest())

        branch_aa_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_aa)
        branch_ab_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_ab)

        # print encode_hex(self.rc.branches(branch_ab_hash)[0])

        branch_aab_hash = self.rc.createBranch(branch_aa_hash, dummy_merkle_root_aab)
        branch_aba_hash = self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba)

        null_test_merkel_root = decode_hex(sha3_256('nulltest').hexdigest())

        failed = False
        try:
            self.rc.createBranch(null_hash, null_test_merkel_root)
        except TransactionFailed:
            failed = True 
        self.assertTrue(failed, "You cannot create a branch with a null parent hash")

        self.assertEqual(self.rc.getBalance(k1_addr, branch_aa_hash), 1000000)

        self.assertTrue(self.rc.isBalanceAtLeast(k1_addr, 1000000, branch_aa_hash))
        self.assertTrue(self.rc.isBalanceAtLeast(k1_addr, 1, branch_ab_hash))
        self.assertFalse(self.rc.isBalanceAtLeast(k1_addr, 1000001, branch_ab_hash))

        failed = False
        try:
            self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba)
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, "You can only create a branch with a given hash once")

        u = self.s.block.gas_used
        self.rc.sendCoin(k2_addr, 500000, branch_aa_hash, sender=t.k1)
        #print "Gas used to send coins after %d blocks: %d" % (2, self.s.block.gas_used - u)

        self.assertEqual(self.rc.getBalance(k2_addr, branch_aa_hash), 500000)
        self.assertEqual(self.rc.getBalance(k2_addr, branch_ab_hash), 0)

        branch_hash = branch_aba_hash
        for i in range(0,100):
            dummy_merkel_root = decode_hex(sha3_256('dummy' + str(i)).hexdigest())
            branch_hash = self.rc.createBranch(branch_hash, dummy_merkel_root)
            # print encode_hex(branch_hash)

        u = self.s.block.gas_used
        self.rc.sendCoin(k2_addr, 500000, branch_hash, sender=t.k1)

        gas_used = self.s.block.gas_used - u
        #print "Gas used to send coins after %d blocks: %d" % (i+1, gas_used)
        # self.assertTrue(u < 130000, "100 branches read in less than 130000 gas")

        failed = False
        try:
            self.rc.sendCoin(k2_addr, 1, branch_aba_hash, sender=t.k1)
        except:
            failed = True


        k0_bal = self.rc.getBalance(k0_addr, branch_ab_hash)
        #print k0_bal
        self.rc.sendCoin(k2_addr, 5, branch_aba_hash, sender=t.k0)
        branch_abaa_hash = self.rc.createBranch(branch_aba_hash, dummy_merkle_root_abaa)
        k0_bal_spent = self.rc.getBalance(k0_addr, branch_abaa_hash)

        #print k0_bal_spent
        self.assertEqual(k0_bal_spent, k0_bal - 5)


        return
        self.assertTrue(failed, "Sending back up to an earlier branch than you have already sent fails")


if __name__ == '__main__':
    main()
