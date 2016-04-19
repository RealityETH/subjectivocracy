from unittest import TestCase, main
from rlp.utils import encode_hex, decode_hex
from ethereum import tester as t
from ethereum import keys
import time
from sha3 import sha3_256


class TestBorgesCoin(TestCase):

    def setUp(self):

        self.s = t.state()
        bc_code = open('bc.sol').read()
        self.bc = self.s.abi_contract(bc_code, language='solidity', sender=t.k0)
        self.bc._constructor(sender=t.k0)
        # print encode_hex(genesis_branch_hash)

    def test_register_and_fetch(self):

        # a
        # aa             ab
        # aaa  aab       aba
        # aaaa aaba aabb abaa

        genesis_hash = decode_hex("01bd7e296e8be10ff0f93bf1b7186d884f05bdc2c293dbc4ca3ea18a5f7c9ebd")

        k0_addr = encode_hex(keys.privtoaddr(t.k0))
        k1_addr = encode_hex(keys.privtoaddr(t.k1))
        k2_addr = encode_hex(keys.privtoaddr(t.k2))

        self.assertEqual(k1_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')
        self.assertEqual(self.bc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        u = self.s.block.gas_used

        self.bc.sendCoin(k1_addr, 1000000, genesis_hash, sender=t.k0)
        # print self.s.block.gas_used - u
        u = self.s.block.gas_used
        # print self.s.block.get_balance(k0_addr)

        self.assertEqual(self.bc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.bc.getBalance(k1_addr, genesis_hash), 1000000)

        dummy_merkle_root_aa = decode_hex(sha3_256('aa').hexdigest())
        dummy_merkle_root_ab = decode_hex(sha3_256('ab').hexdigest())

        dummy_merkle_root_aab = decode_hex(sha3_256('aab').hexdigest())
        dummy_merkle_root_aba = decode_hex(sha3_256('aba').hexdigest())
        dummy_merkle_root_abb = decode_hex(sha3_256('abb').hexdigest())

        dummy_merkle_root_aaaa = decode_hex(sha3_256('aaaa').hexdigest())
        dummy_merkle_root_aaba = decode_hex(sha3_256('aaba').hexdigest())

        branch_aa_hash = self.bc.createBranch(genesis_hash, dummy_merkle_root_aa)
        branch_ab_hash = self.bc.createBranch(genesis_hash, dummy_merkle_root_ab)

        branch_aab_hash = self.bc.createBranch(branch_aa_hash, dummy_merkle_root_aab)
        branch_aba_hash = self.bc.createBranch(branch_ab_hash, dummy_merkle_root_aba)

        self.assertEqual(self.bc.getBalance(k1_addr, branch_aa_hash), 1000000)

        self.assertTrue(self.bc.isBalanceAtLeast(k1_addr, 1000000, branch_aa_hash))
        self.assertTrue(self.bc.isBalanceAtLeast(k1_addr, 1, branch_ab_hash))
        self.assertFalse(self.bc.isBalanceAtLeast(k1_addr, 1000001, branch_ab_hash))

        u = self.s.block.gas_used
        self.bc.sendCoin(k2_addr, 500000, branch_aa_hash, sender=t.k1)
        print "Gas used after %d blocks: %d" % (2, self.s.block.gas_used - u)

        self.assertEqual(self.bc.getBalance(k2_addr, branch_aa_hash), 500000)
        self.assertEqual(self.bc.getBalance(k2_addr, branch_ab_hash), 0)

        branch_hash = branch_aba_hash
        for i in range(0,10):
            dummy_merkel_root = decode_hex(sha3_256('dummy' + str(i)).hexdigest())
            branch_hash = self.bc.createBranch(branch_hash, dummy_merkel_root)
            # print encode_hex(branch_hash)

        u = self.s.block.gas_used
        self.bc.sendCoin(k2_addr, 500000, branch_hash, sender=t.k1)
        print "Gas used after %d blocks: %d" % (i+1, self.s.block.gas_used - u)
        return

         


if __name__ == '__main__':
    main()
