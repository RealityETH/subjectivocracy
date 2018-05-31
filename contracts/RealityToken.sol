  pragma solidity ^0.4.6;

  contract RealityToken {

      event Approval(address indexed _owner, address indexed _spender, uint _value, bytes32 branch);
      event Transfer(address indexed _from, address indexed _to, uint _value, bytes32 branch);
      event BranchCreated(bytes32 hash, address data_cntrct);
      event FundedDistributionContract(address contract_funded, int256 funding_amount);

      bytes32 constant NULL_HASH = "";
      address constant NULL_ADDRESS = 0x0;

      struct Branch {
          bytes32 parent_hash; // Hash of the parent branch.
          bytes32 merkle_root; // Merkle root of the data we commit to
          address arbitrator_list; // Optional address of a contract containing arbitrators with good values
          uint256 timestamp; // Timestamp branch was mined
          uint256 window; // Day x of the system's operation, starting at UTC 00:00:00
          mapping(address => int256) balance_change; // user debits and credits
      }
      mapping(bytes32 => Branch) public branches;

      // Spends, which may cause debits, can only go forwards.
      // That way when we check if you have enough to spend we only have to go backwards.
      mapping(address => uint256) public last_debit_windows; // index of last user debits to stop you going backwards

      mapping(uint256 => bytes32[]) public window_branches; // index to easily get all branch hashes for a window
      uint256 public genesis_window_timestamp; // 00:00:00 UTC on the day the contract was mined

      mapping(address => mapping(address => mapping(bytes32=> uint256))) allowed;


      function RealityToken()
      public {
          genesis_window_timestamp = now - (now % 86400);
          bytes32 genesis_merkle_root = keccak256("I leave to several futures (not to all) my garden of forking paths");
          bytes32 genesis_branch_hash = keccak256(NULL_HASH, genesis_merkle_root, NULL_ADDRESS);
          branches[genesis_branch_hash] = Branch(NULL_HASH, genesis_merkle_root, NULL_ADDRESS, now, 0);
          branches[genesis_branch_hash].balance_change[msg.sender] = 2100000000000000;
          window_branches[0].push(genesis_branch_hash);
      }

      function createBranch(bytes32 parent_branch_hash, bytes32 merkle_root, address arbitrator_list, address contract_funded, int256 funding_amount)
      public returns (bytes32) {
          uint256 window = (now - genesis_window_timestamp) / 86400; // NB remainder gets rounded down

          bytes32 branch_hash = keccak256(parent_branch_hash, merkle_root, arbitrator_list);
          require(branch_hash != NULL_HASH);

          // Your branch must not yet exist, the parent branch must exist.
          // Check existence by timestamp, all branches have one.
          require(branches[branch_hash].timestamp == 0);
          require(branches[parent_branch_hash].timestamp > 0);

          // We must now be a later 24-hour window than the parent.
          require(branches[parent_branch_hash].window < window);

          branches[branch_hash] = Branch(parent_branch_hash, merkle_root, arbitrator_list, now, window);
          window_branches[window].push(branch_hash);

          // distribute further RealityTokens when requested via subjectiviocracy
          if (funding_amount > 0) {
              branches[branch_hash].balance_change[contract_funded] += funding_amount;
              emit FundedDistributionContract(contract_funded, funding_amount);
          }

          emit BranchCreated(branch_hash, arbitrator_list);
          return branch_hash;
      }

      function getWindowBranches(uint256 window)
      public constant returns (bytes32[]) {
          return window_branches[window];
      }

      function approve(address _spender, uint256 _amount, bytes32 _branch)
      public returns (bool success) {
          allowed[msg.sender][_spender][_branch] = _amount;
          emit Approval(msg.sender, _spender, _amount, _branch);
          return true;
      }

      function allowance(address _owner, address _spender, bytes32 branch)
      constant public returns (uint remaining) {
          return allowed[_owner][_spender][branch];
      }

      function balanceOf(address addr, bytes32 branch)
      public constant returns (uint256) {
          int256 bal = 0;
          while(branch != NULL_HASH) {
              bal += branches[branch].balance_change[addr];
              branch = branches[branch].parent_hash;
          }
          return uint256(bal);
      }

      // Crawl up towards the root of the tree until we get enough, or return false if we never do.
      // You never have negative total balance above you, so if you have enough credit at any point then return.
      // This uses less gas than balanceOfAbove, which always has to go all the way to the root.
      function isAmountSpendable(address addr, uint256 _min_balance, bytes32 branch_hash)
      public constant returns (bool) {
          require (_min_balance <= 2100000000000000);
          int256 bal = 0;
          int256 min_balance = int256(_min_balance);
          while(branch_hash != NULL_HASH) {
              bal += branches[branch_hash].balance_change[addr];
              branch_hash = branches[branch_hash].parent_hash;
              if (bal >= min_balance) {
                  return true;
              }
          }
          return false;
      }

      function transferFrom(address from, address addr, uint256 amount, bytes32 branch)
      public returns (bool) {

          require(allowed[from][msg.sender][branch] >= amount);

          uint256 branch_window = branches[branch].window;

          require(amount <= 2100000000000000);
          require(branches[branch].timestamp > 0); // branch must exist

          if (branch_window < last_debit_windows[from]) return false; // debits can't go backwards
          if (!isAmountSpendable(from, amount, branch)) return false; // can only spend what you have

          last_debit_windows[from] = branch_window;
          branches[branch].balance_change[from] -= int256(amount);
          branches[branch].balance_change[addr] += int256(amount);

          uint256 allowed_before = allowed[from][msg.sender][branch];
          uint256 allowed_after = allowed_before - amount;
          assert(allowed_before > allowed_after);

          emit Transfer(from, addr, amount, branch);

          return true;
      }

      function transfer(address addr, uint256 amount, bytes32 branch)
      public returns (bool) {
          uint256 branch_window = branches[branch].window;

          require(amount <= 2100000000000000);
          require(branches[branch].timestamp > 0); // branch must exist

          if (branch_window < last_debit_windows[msg.sender]) return false; // debits can't go backwards
          if (!isAmountSpendable(msg.sender, amount, branch)) return false; // can only spend what you have

          last_debit_windows[msg.sender] = branch_window;
          branches[branch].balance_change[msg.sender] -= int256(amount);
          branches[branch].balance_change[addr] += int256(amount);

          emit Transfer(msg.sender, addr, amount, branch);

          return true;
      }

      function getArbitratorList(bytes32 _branch)
      public constant returns (address) {
          return branches[_branch].arbitrator_list;
      }

      function getWindowOfBranch(bytes32 _branchHash)
      public constant returns (uint id) {
          return branches[_branchHash].window;
      }

      function isBranchInBetweenBranches(bytes32 investigationHash, bytes32 hashOlderBranch, bytes32 hashNewerBranch)
      public constant returns(bool) {
        bytes32 iterationHash=hashNewerBranch;
        while(iterationHash != hashOlderBranch) {
          if(investigationHash == iterationHash) {
            return true;
          }
          else {
              iterationHash = branches[iterationHash].parent_hash;
          }
        }
        return false;
      }

      function getTimestampOfBranch(bytes32 branch) public view returns(uint256){
          return branches[branch].timestamp;
      }

      function getParentBranch(bytes32 branch) public view returns(bytes32){
          return branches[branch].parent_hash;
      }

  }