# Contract interactions, L1-governed design
### Edmund Edgar, 2021-04-01

## Contracts:

* L1.TokenA: A normal Ethereum-native token, eg DAI or WETH.
* L1.TokenAWrapper: A contract that wraps TokenA on L1 to send it L2.
* L2.TokenA: A token, native to L1 but with a proxy on L2. Anywhere this is used on L2 a native token can also be used.

* L2.NativeTokenA: A forkable token native to L2

* L1.GovToken: A dedicated governance token that can be forked on L1. There is only one per fork. In forks this must be committed to one fork or the other.

* L2.Reality.eth: A normal ERC20-capable reality.eth instance on L2. Uses NativeTokenA. There may be other instances supporing other tokens.
* L1.Reality.eth: A forkable ERC20-capable reality.eth instance on L1, using GovToken for bonds.

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

    [uncontested arbitration after 1 week? Complete an arbitration]
```

### Complete an arbitration         
```
    Dave    L2  WhitelistArbitrator.completeArbitration(question_id)
                    NativeTokenA.transfer(Dave, 1000000)
                    RealityETH.submitAnswerByArbitrator(question_id, 1, Bob)

    [arbitration contested   ? Contest an arbitration]
    [arbitration uncontested ? Settle a crowdfund]
```
                                                
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

    [delist question finalizes as 1 ? Complete an arbitration removal]
    [delist question finalizes as 0 ? Cancel an arbitration removal]

    [question goes to arbitration? See [Challenge an arbitration result]
```

### Cancel an arbitrator removal
```
   Bob     L1  ForkManager.unfreezeArbitrator(contest_question_id)
                RealityETH.resultFor(contest_question_id)
                BridgeToL2.sendMessage("WhitelistArbitrator.unFreezeArbitrator(ArbitratorA)")

    [Redeem an arbitration]
```

### Complete arbitrator removal    
```
    Charlie L1  ForkManager.completeArbitratorRemoval(contest_question_id) 
                    RealityETH.resultFor(contest_question_id)
                    BridgeToL2.sendMessage("WhitelistArbitrator.removeArbitrator(ArbitratorA)")

    [Handle an arbitration]                 
```

### Challenge an arbitration result
```
    Bob     L1  ForkManager.requestArbitration(contest_question_id)
                    f1 = self.clone(now + 7 days)
                        RealityETHFork1 = RealityETH.clone() 
                        BridgeToL2.clone()
                        # Burn RealityETH balance
                        # Mint same balance on clone
                        RealityETHFork1.migrateQuestion(contest_question_id)
                        RealityETHFork1.submitAnswerByArbitrator(contest_question_id, 1)
                    f2 = self.clone(now + 7 days)
                        RealityETHFork2 = RealityETH.clone() 
                        BridgeToL2.clone()
                        # Burn RealityETH balance
                        # Mint same balance on clone
                        RealityETHFork2.migrateQuestion(contest_question_id)
                        RealityETHFork2.submitAnswerByArbitrator(contest_question_id, 0)
                    RealityETH.freeze()

    [ On fork date, someone can do [Complete an arbitrator removal] and [Cancel an arbitrator removal] on the respective chains. ]
```

### Cancel a governance proposition when we fork over a different governance proposition
```
    Bob     L1  RealityETH.cancelQuestion(history) 
                    GovToken.transfer(Bob, 100)
                    GovToken.transfer(Charlie, 200)
```

### Buy Accumulated Tokens for GovTokens
```
    Eric    L2  NativeTokenA.approve(deposit)
    Eric    L2  orderer_id = WhitelistArbitrator.reserveTokens(num, min_price, deposit)
                    NativeTokenA.transferFrom(Eric, self, deposit)

    Eric    L1  ForkManager.buyTokens(WhitelistArbitrator, order_id)
                    # Burn own GovTokens
                    BridgeToL2.sendMessage("WhitelistArbitrator.buyTokens", order_id)

    [bot]   L2  BridgeFromL1.processQueue() # or similar
                    WhitelistArbitrator.completeTokenSale(order_id)
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
                    BridgeToL1.sendMessage("mint(Bob, 123"))

    [bot]     L1  TokenWrapper.handleMessage(txid, "mint(Bob, 123"))
                    ForkManager.requireNotInGoveranceFreeze() # NB If bridges and L2 can't go wrong we don't need this
                    ForkManager.requiredBridges()
                    # for each bridge, usually 1 but during forks there are 2
                    BridgeToL2.requireTxExists(txid)
                    TokenA.transfer(Bob, 123)
```

### Moving tokens to L2
```
    Alice   l1  
                TokenA.approve(TokenWrapper, 123)
                TokenWrapper.sendToL2(123)
                    ForkManager.requiredBridges()
                    # for each bridge, usually 1 but during forks there are 2
                    BridgeToL2.sendMessage("mint(Alice, 123)")
```              
