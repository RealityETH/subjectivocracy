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
        #window_branches = self.rc.getWindowBranches(0)
        genesis_branch_hash = self.rc.window_branches(0, 0)
        #print encode_hex(genesis_branch_hash)
        self.assertEqual(len(genesis_branch_hash), 32)


    def test_register_and_fetch(self):

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

        self.assertEqual(self.rc.balanceOfAbove(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        u = self.s.block.gas_used

        self.rc.transferOnBranch(k1_addr, 1000000, genesis_hash, sender=t.k0)

        # self.s.block.timestamp = self.s.block.timestamp + 100
        # self.s = t.state()

        # print self.s.block.gas_used - u
        u = self.s.block.gas_used
        # print self.s.block.get_balance(k0_addr)

        window_index = 4 # index of genesis hash in struct

        self.assertEqual(self.rc.balanceOfAbove(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.rc.balanceOfAbove(k1_addr, genesis_hash), 1000000)

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
            branch_aa_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_aa, contract_addr)
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, "You can't build on a block in the window in which it was created")

        self.s.block.timestamp = self.s.block.timestamp + 86400
        branch_aa_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_aa, contract_addr)
        self.assertEqual(1, len(self.rc.getWindowBranches(1)))
        self.assertEqual([branch_aa_hash], self.rc.getWindowBranches(1))

        aa_branch = self.rc.branches(branch_aa_hash);
        self.assertEqual(1, aa_branch[window_index], "First branch window is 1")

        self.s.block.timestamp = self.s.block.timestamp + ( 86400 * 3 )
        self.s.mine(1)
        self.s.block.timestamp = self.s.block.timestamp + 86400

        branch_ab_hash = self.rc.createBranch(genesis_hash, dummy_merkle_root_ab, contract_addr)

        ab_branch = self.rc.branches(branch_ab_hash);
        self.assertEqual(5, ab_branch[window_index], "window of branch created a few days later is 5, despite having skipped several days")

        self.s.mine(1)
        self.s.block.timestamp = self.s.block.timestamp + 86400

        # print encode_hex(self.rc.branches(branch_ab_hash)[0])

        branch_aab_hash = self.rc.createBranch(branch_aa_hash, dummy_merkle_root_aab, contract_addr)
        branch_aba_hash = self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba, contract_addr)
        self.assertEqual(2, len(self.rc.getWindowBranches(6)))
        self.assertEqual([branch_aab_hash, branch_aba_hash], self.rc.getWindowBranches(6))

        self.s.mine(1)
        self.s.block.timestamp = self.s.block.timestamp + 86400

        null_test_merkle_root = decode_hex(sha3_256('nulltest').hexdigest())

        failed = False
        try:
            self.rc.createBranch(null_hash, null_test_merkle_root, contract_addr)
            self.s.mine(1)
            self.s.block.timestamp = self.s.block.timestamp + 86400
        except TransactionFailed:
            failed = True 
        self.assertTrue(failed, "You cannot create a branch with a null parent hash")

        self.assertEqual(self.rc.balanceOfAbove(k1_addr, branch_aa_hash), 1000000)

        self.assertTrue(self.rc.isAmountSpendable(k1_addr, 1000000, branch_aa_hash))
        self.assertTrue(self.rc.isAmountSpendable(k1_addr, 1, branch_ab_hash))
        self.assertFalse(self.rc.isAmountSpendable(k1_addr, 1000001, branch_ab_hash))

        failed = False
        try:
            self.rc.createBranch(branch_ab_hash, dummy_merkle_root_aba, contract_addr)
            self.s.mine(1)
            self.s.block.timestamp = self.s.block.timestamp + 86400
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, "You can only create a branch with a given hash once")

        u = self.s.block.gas_used
        self.rc.transferOnBranch(k2_addr, 500000, branch_aa_hash, sender=t.k1)
        #print "Gas used to send coins after %d blocks: %d" % (2, self.s.block.gas_used - u)

        self.assertEqual(self.rc.balanceOfAbove(k2_addr, branch_aa_hash), 500000)
        self.assertEqual(self.rc.balanceOfAbove(k2_addr, branch_ab_hash), 0)

        branch_hash = branch_aba_hash
        for i in range(0,100):
            dummy_merkle_root = decode_hex(sha3_256('dummy' + str(i)).hexdigest())
            branch_hash = self.rc.createBranch(branch_hash, dummy_merkle_root, contract_addr)
            self.s.mine(1)
            self.s.block.timestamp = self.s.block.timestamp + 86400
            # print encode_hex(branch_hash)

        u = self.s.block.gas_used
        self.rc.transferOnBranch(k2_addr, 500000, branch_hash, sender=t.k1)

        gas_used = self.s.block.gas_used - u
        print "Gas used to send coins after %d blocks: %d" % (i+1, gas_used)
        # self.assertTrue(u < 130000, "100 branches read in less than 130000 gas")

        failed = False
        try:
            self.rc.transferOnBranch(k2_addr, 1, branch_aba_hash, sender=t.k1)
        except:
            failed = True


        k0_bal = self.rc.balanceOfAbove(k0_addr, branch_ab_hash)
        #print k0_bal
        self.rc.transferOnBranch(k2_addr, 5, branch_aba_hash, sender=t.k0)
        branch_abaa_hash = self.rc.createBranch(branch_aba_hash, dummy_merkle_root_abaa, contract_addr)
        self.s.mine(1)
        self.s.block.timestamp = self.s.block.timestamp + 86400
        k0_bal_spent = self.rc.balanceOfAbove(k0_addr, branch_abaa_hash)

        #print k0_bal_spent
        self.assertEqual(k0_bal_spent, k0_bal - 5)

        self.assertFalse(self.rc.transferOnBranch(k2_addr, 5, branch_ab_hash, sender=t.k0), "Attempting to send coins on an earlier branch returns false")
        self.assertEqual(k0_bal_spent, k0_bal - 5, "Attempt to send coins on an earlier branch left balance unchanged")
        return


if __name__ == '__main__':
    main()
