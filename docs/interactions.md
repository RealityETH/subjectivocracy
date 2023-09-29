# Contract interactions, L2-governed design
### Edmund Edgar, 2023-04-13

This document describes the interactions between actors (users and contracts) in the single-token L2-governed version of the BORG design.

For simplicity some contract parameters are omitted. Details of the mechanism for sending messages between L1 and L2 will depend on the L2 mechanism.

## Contracts:

### Tokens
* L1.GasToken: A normal Ethereum-native token, eg DAI or WETH.
* L2.GasToken: A representation of the L1.GasToken, bridged to it. 

* L2.NativeGasToken: A forkable token native to L2. There may be many of these.
* L1.GovToken, aka L1.ForkManager: A dedicated governance token that can be forked on L1. There is only one per fork. In forks this must be committed to one fork or the other. Can also replace itself while preserving balances.

### Reality.eth instances
* L2.Reality.eth: A normal ERC20-capable reality.eth instance on L2. Uses NativeGasToken. There may be other instances supporing other tokens.
* L1.Reality.eth: A forkable ERC20-capable reality.eth instance on L1, using GovToken for bonds.

### L1-L2 Bridges
* L2.BridgeToL1: A contract sending messages between ledgers.
* L1.BridgeToL2: 
* L2.BridgeFromL1: 
* L1.BridgeFromL2: 

ForkArbitrator

## Operations


### Make a crowdfund            
```
    Alice   L2  question_id = RealityETH.askQuestion(recipient=Bob, arbitrator=AdjudicationFramework)
    Alice   L2  Crowdfunder.createCrowdFund(question_id, value=1234)
```

### Report an answer (uncontested)  
```
    Bob     L2  RealityETH.submitAnswer(question_id, 100, value=100)
```

Next step: 
* Uncontested? [Claim a payout](#claim-a-payout)
* Contested? [Report an answer (contested)](#report-an-answer-contested)

### Claim a payout                  
```
    Bob     L2  RealityETH.claimWinnings(question_id)
```

### Settle a crowdfund              
```
    Bob     L2  Crowdfunder.payOut(question_id)
                   RealityETH.resultFor(question_id)
                    -> pays Bob
```

### Report an answer (contested)
```
    Bob     L2  RealityETH.submitAnswer(question_id, value=100)
    Charlie L2  RealityETH.submitAnswer(question_id, value=200)
    Bob     L2  RealityETH.submitAnswer(question_id, value=400)
    Charlie L2  RealityETH.submitAnswer(question_id, value=2000000)
```

### Contest an answer
```
    Bob     L2  AdjudicationFramework.requestArbitration(question_id, value=1000000)
```

### Handle an arbitration           
```
    Dave    L2  ArbitratorA.requestArbitration(question_id, value=500000)
                    AdjudicationFramework.notifyOfArbitrationRequest(question_id, Dave)

    Arby    L2  ArbitratorA.submitAnswerByArbitrator(question_id, 1, Dave)
                    AdjudicationFramework.submitAnswerByArbitrator(question_id, 1, Bob)
```
Next step:
* Uncontested arbitration after 1 week? [Execute an arbitration](#execute-an-arbitration)
* May be contested: [Contest an arbitration](#contest-an-arbitration)

### Execute an arbitration         
```
    Dave    L2  AdjudicationFramework.executeArbitration(question_id)
                    NativeGasToken.transfer(Dave, 1000000)
                    RealityETH.submitAnswerByArbitrator(question_id, 1, Bob)
```
Next step:
* Arbitration contested? [Contest an arbitration](#contest-an-arbitration)
* Arbitration uncontested? [Settle a crowdfund](#settle-a-crowdfund)
                                                
### Contest an arbitration          
```
    Charlie L2  AdjudicationFramework.beginRemoveArbitrator(address arbitrator_to_remove) 
                contest_question_id = RealityETH.askQuestion("should we delist ArbitratorA?")
    Charlie L2  RealityETH.submitAnswer(contest_question_id, 1, value=2000000)
    Charlie L2  AdjudicationFramework.freezeArbitrator(contest_question_id)
                    RealityETH.getBestAnswer(contest_question_id)
                    RealityETH.getBond(contest_question_id)
```
Next step:
* Delist question finalizes as 1? [Execute an arbitrator removal](#execute-an-arbitrator-removal)
* Delist question finalizes as 0? [Cancel an arbitrator removal](#cancel-an-arbitrator-removal)
* May be contested: [Challenge an arbitration result](#challenge-an-arbitration-or-governance-result)

### Cancel an arbitrator removal
```
   Bob     L2  ForkManager.unfreezeArbitrator(contest_question_id)
                    RealityETH.resultFor(contest_question_id)

```
Next step: 
* [Redeem an arbitration](#redeem-an-arbitration)

### Execute an arbitrator removal   
```
    Charlie L2  AdjudicationFramework.removeArbitrator(contest_question_id) 
                    RealityETH.resultFor(contest_question_id)

Next step:
* [Handle an arbitration](#handle-an-arbitration) to arbitrate the question again with a different arbitrator

### Propose an arbitrator addition
```
    Charlie L2  ForkManager.beginAddArbitratorToWhitelist(whitelist_arbitrator, ArbitratorA) 
                    contest_question_id = RealityETH.askQuestion("should we add ArbitratorA to AdjudicationFramework?")
    Charlie L2  RealityETH.submitAnswer(contest_question_id, 1, value=2000000)
```
Next step:
* [Execute an arbitrator addition](#execute-an-arbitrator-addition) if it finalizes as 1
* Nothing to do if it finalizes as 0
* May be escalated to [Challenge an arbitrator or governance result](#challenge-an-arbitration-or-governance-result) and create a fork

### Execute  an arbitrator addition
```
    Charlie L2  RealityETH.finalizeQuestion(add_question_id)
    Charlie L2  ForkManager.addArbitrator(add_question_id) 
                    RealityETH.resultFor(add_question_id)

```

### Challenge an arbitration or governance result
```
    Bob     L2  ForkArbitrator.requestArbitration(contest_question_id, uint256 max_previous, ...)
                    # Marks this question done and freezes everything else
                    RealityETH.notifyOfArbitrationRequest(contest_question_id, msg.sender, max_previous, value=999999);
                    L2.IncentivizedMarket = createIncentivizedMarket() 
                    Bridge.requestFork()

    [bot]   L1  ForkManager.startFork()

    Bob     L1  ForkManager.deployFork(false, contested question data)
                # Clones ForkManager
                # Clones Bridge
                # Copies contested question to child RealityETH

    Charlie L1  ForkManager.deployFork(true, contested question data)
                # Clones ForkManager
                # Clones Bridge
                # Copies contested question to child RealityETH

```

Next step:
* Wait for the fork date, then anyone can [Execute an arbitrator removal](#execute-an-arbitrator-removal) on one chain and [Cancel an arbitrator removal](#cancel-an-arbitrator-removal) on the other.


### Bid in the auction
```
    Bob    L2   IncentivizedMarket.bid(uint256 yes_price_percent, value=tokens)
                    # burns own tokens
                    # fork.mint(msg.sender, tokens)

                # Wait 1 week
                IncentivizedMarket.calculateClearingPrice()

          L2    .getYesNo()
                withdraw()
                    # check clearing price
                    # decide which side the user is on by whether their price is above or below the clearing percent
                    # give them tokens, multiplied by inverse of clearing percent

            * ISSUE: Is there a simple implementation of an auction with incentivized liquidity


    Move burned funds into two pools on L1
    Sell the burned funds in return for token A or token B on a curve
    See which has the most tokens unsold, that one is more valuable
      eg 10000 F1+F2 split into 10000 F1 and 10000 F2
         First F1 sells for 0.01 ETH
         Second F1 sells for 0.02 ETH
    

```





### Propose a routine governance change
```
    Charlie L1  ForkManager.beginUpgradeBridge
                    gov_question_id = RealityETH.askQuestion("should we do a routine upgrade to ForkManager XYZ?")

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
    Charlie L1  ForkManager.beginUpgradeBridge
        gov_question_id = RealityETH.askQuestion("should we freeze exits and upgrade to ForkManager XYZ?")
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
    Charlie L1  ForkManager.executeBridgeUpdate(gov_question_id) 
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
* If the question is still relevant it can be begun again on either chain or both.


-> DELETE ALL THE ACCUMULATED TOKEN STUFF AND JUST BURN THE TOKENS?
   Alternatively, move them over via the bridge


### Buy Accumulated Tokens by burning GovTokens
```
    Eric    L2  NativeGasToken.approve(deposit)
    Eric    L2  orderer_id = AdjudicationFramework.reserveTokens(num, min_price, deposit)
                    NativeGasToken.transferFrom(Eric, self, deposit)

    Eric    L1  ForkManager.executeTokenSale(AdjudicationFramework, reservation_id, num_gov_tokens_paid)
                    # Burn own GovTokens
                    BridgeToL2.sendMessage("AdjudicationFramework.executeTokenSale", reservation_id, num_gov_tokens_paid)

    [bot]   L2  BridgeFromL1.processQueue() # or similar
                    AdjudicationFramework.executeTokenSale(reservation_id)
                        NativeGasToken.transfer(Eric, deposit+num)
```

### Unlock funds from a timed-out sale
```
    Frank   L2  AdjudicationFramework.cancelTimedOutOrder(order_id)
                    # Makes funds reserved for Eric and his deposit available for someone else to order
```

### Outbid a low reservation
```
    Frank   L2  AdjudicationFramework.outBidReservation(num, price, nonce, resid)
                    # Replace a bid
```

### Moving tokens to L2
```
    Alice   L1  
                GasToken.approve(GasTokenWrapper, 123)
                GasTokenWrapper.sendToL2(123)
                    ForkManager.requiredBridges()
                    # for each bridge, usually 1 but during forks there are 2
                    BridgeToL2.sendMessage("mint(Alice, 123)")

    [bot]   L2  BridgeFromL2.processQueue() # or similar
                    GasToken.mint(Alice, 123) 
```

### Unlocking tokens on L1
```
    Bob     L1  GasToken.sendToL1(123)
                    BridgeToL1.sendMessage("GasTokenWrapper.mint(Bob, 123"))

    [bot]   L1  BridgeFromL2.processQueue() or similar 
                    GasTokenWrapper.receiveFromL2(Bob, 123)
                        ForkManager.requiredBridges()
                        # If we the transfer cannot be completed, we queue the message. 
                        # This happens if need to hear from 2 bridges or wait for something to be updated/unfrozen
                        GasToken.transfer(Bob, 123)
```

### Completing a move from L2 that resulted in a queued message because of a fork or governance freeze

    Bob     L1  GasTokenWrapper.retryMessage(Bob, 123, bridge_contract)
                    ForkManager.requiredBridges()
                    GasToken.transfer(Bob, 123)

### Notifying a token bridge after a fork

    Alice   L1  GasTokenWrapper.updateForkManager()
                    ForkManager.replacedByForkManager()

