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

        token_code = open('token.sol').read()
        standardtoken_code = open('standardtoken.sol').read()
        realitytoken_code = open('realitytoken.sol').read()
        realitytokenfactory_code = open('realitytokenfactory.sol').read()

        #all_code = token_code + standardtoken_code + realitytoken_code + realitytokenfactory_code
        self.rc_code = token_code + standardtoken_code + realitytoken_code

        NULL_ADDRESS = decode_hex("0000000000000000000000000000000000000000")

        self.genesis_window_timestamp = self.s.block.timestamp

        self.rc0 = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        # Should really be called via the constructor
        self.rc0.initialize(0, NULL_ADDRESS, keys.privtoaddr(t.k0));
        self.assertEqual(self.rc0.getWindowForTimestamp(self.s.block.timestamp), 0)

        rc0addr = self.rc0.address
        #self.assertEqual(self.rc0.getWindowForTimestamp(self.s.block.timestamp), 1)
        self.assertEqual(self.s.block.timestamp, self.genesis_window_timestamp)

        self.s.block.timestamp = self.s.block.timestamp + 86400

        self.rc1a = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        # Should really be called via the constructor
        self.rc1a.initialize(0, rc0addr, keys.privtoaddr(t.k1));
        self.assertEqual(self.rc0.getWindowForTimestamp(self.s.block.timestamp), 1)

        #window_branches = self.rc.getWindowBranches(0)
        #genesis_branch_hash = self.rc.window_branches(0, 0)
        #print encode_hex(genesis_branch_hash)
        #self.assertEqual(len(genesis_branch_hash), 32)


    def test_simple_sending(self):

        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), 2100000000000000)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), 0)
        self.rc0.transfer(keys.privtoaddr(t.k1), 100000000000000, sender=t.k0);
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), 2000000000000000)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), 100000000000000)

    def test_simple_sending_on_early_branch(self):

        self.assertEqual(self.rc1a.last_parent_window(), 0)
        #self.rc1a.copyBalanceFromParent(keys.privtoaddr(t.k0))
        #self.rc1a.copyBalanceFromParent(keys.privtoaddr(t.k1))
        self.assertEqual(self.rc1a.balanceOf(keys.privtoaddr(t.k0)), 2100000000000000)
        self.assertEqual(self.rc1a.balanceOf(keys.privtoaddr(t.k1)), 0)
        self.rc1a.transfer(keys.privtoaddr(t.k1), 100000000000000, sender=t.k0);
        self.assertEqual(self.rc1a.balanceOf(keys.privtoaddr(t.k1)), 100000000000000)
        self.assertEqual(self.rc1a.balanceOf(keys.privtoaddr(t.k0)), 2000000000000000)

        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), 2100000000000000, "Moving funds on the fork doesn't affect the parent")
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), 0, "Moving funds on the fork doesn't affect the parent")
        return

    def test_balance_deduction_on_fork(self):

        # Start with these balances on window 1
        k0bal = 2100000000000000
        k1bal = 0

        self.assertEqual(self.rc0.getWindowForTimestamp(self.s.block.timestamp), 1)

        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), k0bal)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), k1bal)

        self.rc0.transfer(keys.privtoaddr(t.k1), 50000000000000, sender=t.k0);
        k0bal = k0bal - 50000000000000
        k1bal = k1bal + 50000000000000
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), k0bal)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), k1bal)

        # Store these balances for when we check forks
        k0balw1 = k0bal
        k1balw1 = k1bal

        # Move forward a couple of days, then send some more funds
        self.s.block.timestamp = self.s.block.timestamp + 86400
        self.s.block.timestamp = self.s.block.timestamp + 86400
        self.assertEqual(self.rc0.getWindowForTimestamp(self.s.block.timestamp), 3)

        self.rc0.transfer(keys.privtoaddr(t.k1), 150000000000000, sender=t.k0);
        k0bal = k0bal - 150000000000000
        k1bal = k1bal + 150000000000000
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), k0bal)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), k1bal)

        self.rc0.transfer(keys.privtoaddr(t.k0), 5, sender=t.k1);
        k0bal = k0bal + 5
        k1bal = k1bal - 5
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k0)), k0bal)
        self.assertEqual(self.rc0.balanceOf(keys.privtoaddr(t.k1)), k1bal)

        # Fork off window 2 (starting on window 3)
        # This should give us the balances before the sends on window 3

        self.rc1b = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        self.rc1b.initialize(2, self.rc0.address, keys.privtoaddr(t.k1));
        self.assertEqual(self.rc1b.balanceOf(keys.privtoaddr(t.k0)), k0balw1)
        self.assertEqual(self.rc1b.balanceOf(keys.privtoaddr(t.k1)), k1balw1)

        # Likewise if we'd forked off window 1
        self.rc1c = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        self.rc1c.initialize(1, self.rc0.address, keys.privtoaddr(t.k1));
        # self.rc1c.copyBalanceFromParent(keys.privtoaddr(t.k0))
        # self.rc1c.copyBalanceFromParent(keys.privtoaddr(t.k1))
        self.assertEqual(self.rc1c.balanceOf(keys.privtoaddr(t.k0)), k0balw1)
        self.assertEqual(self.rc1c.balanceOf(keys.privtoaddr(t.k1)), k1balw1)

        self.rc1c.transfer(keys.privtoaddr(t.k0), 9, sender=t.k1);
        self.assertEqual(self.rc1c.balanceOf(keys.privtoaddr(t.k0)), k0balw1 + 9)
        self.assertEqual(self.rc1c.balanceOf(keys.privtoaddr(t.k1)), k1balw1 - 9)

        # Try to fork off window 3.
        # This should fail, because it's still window 3.

        failed = False
        self.rc1d = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        try:
            self.rc1d.initialize(3, self.rc0.address, keys.privtoaddr(t.k1));
        except TransactionFailed:
            failed = True
        self.assertTrue(failed, 'You cannot fork off a point until the window after it.')

        self.s.block.timestamp = self.s.block.timestamp + 86400
        self.rc1d.initialize(3, self.rc0.address, keys.privtoaddr(t.k1));



        self.rc1c1 = self.s.abi_contract(self.rc_code, language='solidity', sender=t.k0)
        self.rc1c1.initialize(3, self.rc0.address, keys.privtoaddr(t.k1));
        self.assertEqual(self.rc1c1.balanceOf(keys.privtoaddr(t.k0)), k0balw1 + 9)


        return
        # a
        # aa             ab
        # aaa  aab       aba
        # aaaa aaba aabb abaa

        return
        self.assertEqual(self.genesis_token.last_parent_window(), 0)

        return

        genesis_hash = decode_hex("fca5e1a248b8fee34db137da5e38b41f95d11feb5a8fa192a150d8d5d8de1c59")

        NULL_HASH = decode_hex("0000000000000000000000000000000000000000000000000000000000000000")
        # print encode_hex(NULL_HASH)

        k0_addr = encode_hex(keys.privtoaddr(t.k0))
        k1_addr = encode_hex(keys.privtoaddr(t.k1))
        k2_addr = encode_hex(keys.privtoaddr(t.k2))

        contract_addr = encode_hex(keys.privtoaddr(t.k9))

        self.assertEqual(k1_addr, '7d577a597b2742b498cb5cf0c26cdcd726d39e6e')

        self.assertEqual(self.rc.balanceOfAbove(keys.privtoaddr(t.k0), keys.privtoaddr(t.k0), genesis_hash), 2100000000000000)

        u = self.s.block.gas_used

        self.rc.transferOnBranch(k1_addr, 1000000, genesis_hash, sender=t.k0)

        # self.s.block.timestamp = self.s.block.timestamp + 100
        # self.s = t.state()

        # print self.s.block.gas_used - u
        u = self.s.block.gas_used
        # print self.s.block.get_balance(k0_addr)

        window_index = 4 # index of genesis hash in struct

        self.assertEqual(self.rc.balanceOfAbove(keys.privtoaddr(t.k0), keys.privtoaddr(t.k0), genesis_hash), 2100000000000000-1000000)
        self.assertEqual(self.rc.balanceOfAbove(k1_addr, k1_addr, genesis_hash), 1000000)

        genesis_branch = self.rc.branches(genesis_hash);
        self.assertEqual(NULL_HASH, genesis_branch[0])
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
            self.rc.createBranch(NULL_HASH, null_test_merkle_root, contract_addr)
            self.s.mine(1)
            self.s.block.timestamp = self.s.block.timestamp + 86400
        except TransactionFailed:
            failed = True 
        self.assertTrue(failed, "You cannot create a branch with a null parent hash")

        self.assertEqual(self.rc.balanceOfAbove(k1_addr, k1_addr, branch_aa_hash), 1000000)

        self.assertTrue(self.rc.isAmountSpendable(k1_addr, k1_addr, 1000000, branch_aa_hash))
        self.assertTrue(self.rc.isAmountSpendable(k1_addr, k1_addr, 1, branch_ab_hash))
        self.assertFalse(self.rc.isAmountSpendable(k1_addr, k1_addr, 1000001, branch_ab_hash))

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

        self.assertEqual(self.rc.balanceOfAbove(k2_addr, k2_addr, branch_aa_hash), 500000)
        self.assertEqual(self.rc.balanceOfAbove(k2_addr, k2_addr, branch_ab_hash), 0)

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


        k0_bal = self.rc.balanceOfAbove(k0_addr, k0_addr, branch_ab_hash)
        #print k0_bal
        self.rc.transferOnBranch(k2_addr, 5, branch_aba_hash, sender=t.k0)
        branch_abaa_hash = self.rc.createBranch(branch_aba_hash, dummy_merkle_root_abaa, contract_addr)
        self.s.mine(1)
        self.s.block.timestamp = self.s.block.timestamp + 86400
        k0_bal_spent = self.rc.balanceOfAbove(k0_addr, k0_addr, branch_abaa_hash)

        #print k0_bal_spent
        self.assertEqual(k0_bal_spent, k0_bal - 5)

        self.assertFalse(self.rc.transferOnBranch(k2_addr, 5, branch_ab_hash, sender=t.k0), "Attempting to send coins on an earlier branch returns false")
        self.assertEqual(k0_bal_spent, k0_bal - 5, "Attempt to send coins on an earlier branch left balance unchanged")
        return


if __name__ == '__main__':
    main()
