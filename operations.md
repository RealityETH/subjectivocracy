# Contract interactions, L1-governed design
### Edmund Edgar, 2021-04-01

## Contracts:

### Tokens
* L1.TokenA: A normal Ethereum-native token, eg DAI or WETH.
* L1.TokenAWrapper: A contract that wraps TokenA on L1 to send it L2.
* L2.TokenA: A representation of the L1.TokenA, bridged to it. Anywhere this is used on L2 here, a native token can also be used.
* L2.NativeTokenA: A forkable token native to L2. There may be many of these.
* L1.GovToken, aka L1.ForkManager: A dedicated governance token that can be forked on L1. There is only one per fork. In forks this must be committed to one fork or the other. Can also replace itself while preserving balances.

### Reality.eth instances
* L2.Reality.eth: A normal ERC20-capable reality.eth instance on L2. Uses NativeTokenA. There may be other instances supporing other tokens.
* L1.Reality.eth: A forkable ERC20-capable reality.eth instance on L1, using GovToken for bonds.

### L1-L2 Bridges
* L2.BridgeToL1: A contract sending messages between ledgers. Details will depend on the L2 implementation, including method signatures
* L1.BridgeToL2: 
* L2.BridgeFromL1: 
* L1.BridgeFromL2: 

## Operations


### Make a crowdfund            
```
    Alice   L2  question_id = RealityETH.askQuestion(recipient=Bob, arbitrator=WhitelistArbitrator)
    Alice   L2  TokenA.approve(Crowdfunder, 1234)
    Alice   L2  Crowdfunder.createCrowdFund(question_id, 1234)
                    TokenA.transferFrom(Alice, self, 1234)
```

### Report an answer (uncontested)  
```
    Bob     L2  NativeTokenA.approve(RealityETH, 100)
    Bob     L2  RealityETH.submitAnswer(question_id, 100)
```

Next step: 
* Uncontested? [Claim a payout](#claim-a-payout)
* Contested? [Report an answer (contested)](#report-an-answer-contested)

### Claim a payout                  
```
    Bob     L2  RealityETH.claimWinnings(question_id)
                    NativeTokenA.transferFrom(Bob, self, 100)
```

### Settle a crowdfund              
```
    Bob     L2  Crowdfunder.payOut(question_id)
                   RealityETH.resultFor(question_id)
                   NativeTokenA.transfer(Bob)
```

### Report an answer (contested)
```
    Bob     L2  NativeTokenA.approve(RealityETH, 100)
    Bob     L2  RealityETH.submitAnswer(question_id, 100)
                    NativeTokenA.transferFrom(Bob, self, 100)
    Charlie L2  NativeTokenA.approve(RealityETH, 200)
    Charlie L2  RealityETH.submitAnswer(question_id, 200)
                    NativeTokenA.transferFrom(Charlie, self, 200)
    Bob     L2  NativeTokenA.approve(RealityETH, 400)
    Bob     L2  RealityETH.submitAnswer(question_id, 400)
                    NativeTokenA.transferFrom(Bob, self, 400)
    Charlie L2  NativeTokenA.approve(RealityETH, 2000000)
    Charlie L2  RealityETH.submitAnswer(question_id, 2000000)
                    NativeTokenA.transferFrom(Charlie, self, 2000000)
```

### Contest an answer
```
    Bob     L2  NativeTokenA.approve(WhitelistArbitrator, 1000000) 
    Bob     L2  WhitelistArbitrator.requestArbitration(question_id)
                    NativeTokenA.transferFrom(Bob, self, 1000000)
```

### Handle an arbitration           
```
    Dave    L2  NativeTokenA.approve(ArbitratorA, 500000) 
    Dave    L2  ArbitratorA.requestArbitration(question_id)
                    NativeTokenA.transferFrom(Dave, self, 500000)
                    WhitelistArbitrator.notifyOfArbitrationRequest(question_id, Dave)

    Arby    L2  ArbitratorA.submitAnswerByArbitrator(question_id, 1, Dave)
                    WhitelistArbitrator.submitAnswerByArbitrator(question_id, 1, Bob)
```
Next step:
* Uncontested arbitration after 1 week? [Execute an arbitration](#execute-an-arbitration)
* May be contested: [Contest an arbitration](#contest-an-arbitration)

### Execute an arbitration         
```
    Dave    L2  WhitelistArbitrator.executeArbitration(question_id)
                    NativeTokenA.transfer(Dave, 1000000)
                    RealityETH.submitAnswerByArbitrator(question_id, 1, Bob)
```
Next step:
* Arbitration contested? [Contest an arbitration](#contest-an-arbitration)
* Arbitration uncontested? [Settle a crowdfund](#settle-a-crowdfund)
                                                
### Contest an arbitration          
```
    Charlie L1  contest_question_id = RealityETH.askQuestion("should we delist ArbitratorA?")
    Charlie L1  TokenX.approve(RealityETH, 2000000)
    Charlie L1  RealityETH.submitAnswer(contest_question_id, 1, 2000000)
    Charlie L1  ForkManager.freezeArbitrator(contest_question_id)
                    RealityETH.getBestAnswer(contest_question_id)
                    RealityETH.getBond(contest_question_id)
                    BridgeToL2.sendMessage("WhitelistArbitrator.freezeArbitrator(ArbitratorA)")
    [bot]   L2  BridgeFromL1.processQueue() # or similar
                    WhitelistArbitrator.freezeArbitrator(ArbitratorA)
```
Next step:
* Delist question finalizes as 1? [Execute an arbitrator removal](#execute-an-arbitrator-removal)
* Delist question finalizes as 0? [Cancel an arbitrator removal](#cancel-an-arbitrator-removal)
* May be contested: [Challenge an arbitration result](#challenge-an-arbitration-or-governance-result)

### Cancel an arbitrator removal
```
   Bob     L1  ForkManager.unfreezeArbitrator(contest_question_id)
                    RealityETH.resultFor(contest_question_id)
                    BridgeToL2.sendMessage("WhitelistArbitrator.unFreezeArbitrator(ArbitratorA)")

   [bot]   L2  BridgeFromL1.processQueue() # or similar
                    WhitelistArbitrator.unFreezeArbitrator(ArbitratorA)
```
Next step: 
* [Redeem an arbitration](#redeem-an-arbitration)

### Execute an arbitrator removal    
```
    Charlie L1  ForkManager.executeArbitratorRemoval(contest_question_id) 
                    RealityETH.resultFor(contest_question_id)
                    BridgeToL2.sendMessage("WhitelistArbitrator.removeArbitrator(ArbitratorA)")

    [bot]   L2  BridgeFromL1.processQueue() # or similar
                    WhitelistArbitrator.removeArbitrator(ArbitratorA)
```
Next step:
* [Handle an arbitration](#handle-an-arbitration) to arbitrate the question again with a different arbitrator

### Challenge an arbitration or governance result
```
    Bob     L1  ForkManager.requestArbitration(contest_question_id, uint256 max_previous)
                    f1 = self.clone(now + 1 days, RealityETH, BridgeToL2, BridgeFromL2)
                        RealityETHFork1 = RealityETH.clone();
                        RealityETHFork1.setParent(address(RealityETH));
                        BridgeToL2.clone()
                        BridgeFromL2.clone()
                        # Burn balance of the question in ourselves
                        # Mint same balance on the cloned token for the new RealityETH
                        RealityETHFork1.importQuestion(contest_question_id, true)
                        RealityETHFork1.submitAnswerByArbitrator(contest_question_id, 1)
                    f2 = self.clone(now + 1 days, RealityETH, BridgeFromL2, BridgeFromL2)
                        RealityETHFork2 = RealityETH.clone() 
                        BridgeFromL2.clone()
                        BridgeToL2.clone()
                        RealityETHFork2.setParent(address(RealityETH));
                        # Burn balance of the question in ourselves
                        # Mint same balance on the cloned token for the new RealityETH
                        RealityETHFork2.importQuestion(contest_question_id, true)
                        RealityETHFork2.submitAnswerByArbitrator(contest_question_id, 0)
                    # Marks this question done and freezes everything else
                    RealityETH.notifyOfArbitrationRequest(contest_question_id, msg.sender, max_previous);

```
Next step:
* Wait for the fork date, then anyone can [Execute an arbitrator removal](#execute-an-arbitrator-removal) on one chain and [Cancel an arbitrator removal](#cancel-an-arbitrator-removal) on the other.

### Propose a routine governance change
```
    Charlie L1  gov_question_id = RealityETH.askQuestion("should we do a routine upgrade to ForkManager XYZ?")
    Charlie L1  TokenX.approve(RealityETH, 2000000)
    Charlie L1  RealityETH.submitAnswer(gov_question_id, 1, 2000000)
```
Next step:
* Upgrade question finalizes as 1? [Execute a governance change](#execute-a-governance-change)
* Upgrade question finalizes as 0? No need to do anything
* May be contested: [Challenge an arbitration result](#challenge-an-arbitration-or-governance-result)

### Finalize a completed governance change
```
    Charlie L1  RealityETH.finalizeQuestion(gov_question_id)
```
Next step: 
* [Execute a governance change](execute-a-governance-change)

NB On the normal non-forkable version of Reality.eth finalization happens automatically without a transaction. 
It's its own transaction on the forkable version because forking for one question affects whether others can finalize, even within the same timestamp.

### Propose an urgent governance change
```
    Charlie L1  gov_question_id = RealityETH.askQuestion("should we freeze exits and upgrade to ForkManager XYZ?")
    Charlie L1  TokenX.approve(RealityETH, 2000000)
    Charlie L1  RealityETH.submitAnswer(gov_question_id, 1, 2000000)
    Charlie L1  ForkManager.freezeBridges(gov_question_id)
                    RealityETH.getBestAnswer(gov_question_id)
                    RealityETH.getBond(gov_question_id)
                    # Update self to say there are no available bridges
```
* Upgrade question finalizes as 1? [Execute a governance change](#execute-a-governance-change)
* Upgrade question finalizes as 0? [Clear a failed urgent governance proposal](#clear-a-failed-urgent-governance-proposal)
* May be contested: [Challenge an arbitration result](#challenge-an-arbitration-or-governance-result)

### Execute a governance change
```
    Charlie L1  ForkManager.executeGovernanceUpdate:(gov_question_id) 
                    RealityETH.resultFor(gov_question_id)
                    # Update to reflect child forkmanager
                    # Has the effect of unfreezing bridges, may be new bridges
```

### Clear a failed urgent governance proposal
```
   Bob     L1  ForkManager.clearFailedGovernanceProposal(contest_question_id)
                    RealityETH.resultFor(contest_question_id)
                    # Update self to say the previous bridge is back in action
```

### Return funds from a governance proposition or arbitrator change proposition when we fork over a different proposition
```
    Bob     L1  RealityETH.refund(history) 
                    GovToken.transfer(Bob, 100)
                    GovToken.transfer(Charlie, 200)
```
Next step:
* The question can be recreated on each chain, [Recreate a question after a fork](recreate-a-question-after-a-fork) 

### Recreate a question after a fork
```
    Bob     L1  RealityETHFork1.importQuestion(question_id, false) # could also be RealityETHFork2
```

### Buy Accumulated Tokens by burning GovTokens
```
    Eric    L2  NativeTokenA.approve(deposit)
    Eric    L2  orderer_id = WhitelistArbitrator.reserveTokens(num, min_price, deposit)
                    NativeTokenA.transferFrom(Eric, self, deposit)

    Eric    L1  ForkManager.buyTokens(WhitelistArbitrator, order_id)
                    # Burn own GovTokens
                    BridgeToL2.sendMessage("WhitelistArbitrator.buyTokens", order_id)

    [bot]   L2  BridgeFromL1.processQueue() # or similar
                    WhitelistArbitrator.executeTokenSale(order_id)
                        NativeTokenA.transfer(Eric, deposit+num)
```

### Unlock funds from a timed-out sale
```
    Frank   L2  WhitelistArbitrator.cancelTimedOutOrder(order_id)
                    # Makes funds reserved for Eric and his deposit available for someone else to order
```

### Unlocking tokens on L1
```
    Bob     L1  TokenA.sendToL1(123)
                    BridgeToL1.sendMessage("TokenAWrappermint(Bob, 123"))

    [bot]   L1  BridgeFromL2.processQueue() or similar 
                    TokenAWrapper.mint(Bob, 123")
                        ForkManager.requiredBridges()
                        # for each bridge, usually 1 but during forks there are 2. If it's zero we're frozen so abort.
                        # TODO: If aborted we need to be able to resend this later, maybe put in another queue?
                        TokenA.transfer(Bob, 123)
```

### Moving tokens to L2
```
    Alice   L1  
                TokenA.approve(TokenAWrapper, 123)
                TokenAWrapper.sendToL2(123)
                    ForkManager.requiredBridges()
                    # for each bridge, usually 1 but during forks there are 2
                    BridgeToL2.sendMessage("mint(Alice, 123)")

    [bot]   L2  BridgeFromL2.processQueue() # or similar
                    TokenA.mint(Alice, 123) 
```
