from unittest import TestCase, main
from rlp.utils import encode_hex, decode_hex
from ethereum import tester as t
from ethereum import keys
import time

class TestBorgesCoin(TestCase):

    def setUp(self):

        self.s = t.state()
        bc_code = open('bc.sol').read()
        self.bc = self.s.abi_contract(bc_code, language='solidity', sender=t.k0)
        self.bc._constructor(sender=t.k0)
        # print encode_hex(genesis_branch_hash)

    def test_register_and_fetch(self):

        genesis_hash = decode_hex("01bd7e296e8be10ff0f93bf1b7186d884f05bdc2c293dbc4ca3ea18a5f7c9ebd")

        bob_addr = encode_hex(keys.privtoaddr(t.k1))
        self.assertEqual(bob_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')
        self.assertEqual(self.bc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        self.bc.sendCoin(bob_addr, 1000000, genesis_hash)
        self.assertEqual(self.bc.getBalance(keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.bc.getBalance(bob_addr, genesis_hash), 1000000)

        dummy_merkle_root = genesis_hash # any bytes32 data will do
        branch_a1_hash = self.bc.createBranch(genesis_hash, dummy_merkle_root)
        self.assertEqual(self.bc.getBalance(bob_addr, branch_a1_hash), 1000000)
        self.assertTrue(self.bc.isBalanceAtLeast(bob_addr, 1000000, branch_a1_hash))
        self.assertTrue(self.bc.isBalanceAtLeast(bob_addr, 1, branch_a1_hash))
        self.assertFalse(self.bc.isBalanceAtLeast(bob_addr, 1000001, branch_a1_hash))
        return

         


if __name__ == '__main__':
    main()
