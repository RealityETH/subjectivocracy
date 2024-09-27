# Contract interactions
### Edmund Edgar, 2023-04-13, last updated 2024-03-12

This document describes the interactions between actors (users and contracts) in Backstop.

For simplicity some contract parameters are omitted. See the tests under /tests for the exact parameters.

### Notation
 * L1. or L2. denotes the layer on which the token contract is deployed
 * .L1Token denotes a token native to L1. .L2Token denotes a token native to L2. 
 * ...X denotes one of many versions (ie there may also be a "Y" and a "Z").
 * ...-1 and ...-2 denote multiple versions that exist after a fork.
 * Alice, Bob are example users, each with a unique sender address (that may exist on both L1 and L2)

## Contracts:

### Tokens

 * L1.L1TokenX: A normal Ethereum-native token, eg DAI or WETH.
 * L2.L1TokenX: A representation of the L1.SomeToken1, bridged to layer 2.

 * L2.L2TokenX: A forkable token issued on L2. There may be many of these.
 * L1.L2TokenX: A representation of the L2.L2TokenX on L1.

 * L1.GovToken, An ERC20 token representing a dedicated governance token that can be forked on L1. There is only one per fork. 
 * L2.GovToken, The native token version of L1.GovToken bridged to L2.

### Reality.eth instances
 * L2.RealityETH: A normal native reality.eth instance on L2. Uses L2.GovToken. There may be other instances supporing other tokens. This role could be played by a different escalation game contract.
 * L1.ForkableRealityETH_ERC20: A forkable ERC20-capable reality.eth instance on L1, using GovToken for bonds. Changing this to a different escalation game contract would require a system upgrade.

### Arbitrators
 * L2.ArbitratorX: A reality.eth arbitrator instance on L2
 * L2.AdjudicationFrameworkRequests: A adjudication framework, ie a whitelist of arbitrators such as L2.ArbitratorX. "Requests" means it uses the pull pattern.
 * L2.L2ForkArbitrator: An arbitrator contract used for escalations by the adjudication framework
 * L1.L1ForkArbitrator: An arbitrator contract used for escalations in governance proposals.

### L1-L2 Bridges
 * L1.ForkableBridge: A bridge contract like zkEVMBridge but forkable and able to handle L2.GovToken as L2 the native token.
 * L2.Bridge: A bridge like a normal zkEVMBridge, but with gas token handling. Does not need to be forkable, but may be to avoid deploying multiple contracts.

### Admin contract
 * L1.ForkableRollupGovernor: A contract with the permission to upgrade the L1 system.

### Forkable system infrastructure
 * L2.L2ChainInfo: A contract on L2 that reports information about which chain it is on, what it forked over etc.
 * L1.L1GlobalChainInfoPublisher: A single contract (usable by all forks) used to send information about the fork to L2.L2ChainInfo.
 * L1.HardAssetManager: A contract that decides which fork unforkable tokens should be transferred to (just using an EOA for now)

### Example contracts
 * L2.CrowdfunderX is an example of a crowdfunding contract you might deploy. We use this a general example of a contract that needs subjectivocratically-secure adjudication.

## Operations

### Make a crowdfund payable if Bob completes a task
```
    Alice   L2.question_id = RealityETH.askQuestion(question="Did Bob finish his job?", arbitrator=AdjudicationFrameworkRequests)
    Alice   L2.CrowdfunderX.createCrowdFund(question_id, value=1234)
```

### Report an answer (uncontested)  
```
    Bob     L2.RealityETH.submitAnswer(question_id, 100, value=100)
```

#### Next step: 

 * Uncontested? [Claim a payout](#claim-a-payout)
 * Contested? [Report an answer (contested)](#report-an-answer-contested)

### Claim a payout                  
```
    Bob     L2.RealityETH.claimWinnings(question_id)
```

### Settle a crowdfund              
```
    Bob     L2.Crowdfunder.payOut(question_id)
                   RealityETH.resultFor(question_id)
                    -> pays Bob
```

### Report an answer (contested)
```
    Bob     L2.RealityETH.submitAnswer(question_id, value=100)
    Charlie L2.RealityETH.submitAnswer(question_id, value=200)
    Bob     L2.RealityETH.submitAnswer(question_id, value=400)
    Charlie L2.RealityETH.submitAnswer(question_id, value=2000000)
```

### Contest an answer
```
    Bob     L2.AdjudicationFrameworkRequests.requestArbitration(question_id, value=1000000)
```

### Handle an arbitration           
```
    Dave    L2.ArbitratorA.requestArbitration(question_id, value=500000)
                    AdjudicationFrameworkRequests.notifyOfArbitrationRequest(question_id, Dave)

    Arby    L2.ArbitratorA.submitAnswerByArbitrator(question_id, 1, Dave)
                    AdjudicationFrameworkRequests.submitAnswerByArbitrator(question_id, 1, Bob)
```
#### Next step:

 * Uncontested arbitration after 1 week? [Execute an arbitration](#execute-an-arbitration)
 * May be contested: [Contest an arbitration](#contest-an-arbitration)

### Execute an arbitration         
```
    Dave    L2.AdjudicationFrameworkRequests.executeArbitration(question_id)
                    RealityETH.submitAnswerByArbitrator(question_id, 1, Bob, value=1000000)
```
#### Next step:

 * Arbitration contested? [Contest an arbitration](#contest-an-arbitration)
 * Arbitration uncontested? [Settle a crowdfund](#settle-a-crowdfund)
                                                
### Contest an arbitration.
```
    Charlie L2.AdjudicationFrameworkRequests.beginRemoveArbitrator(address arbitrator_to_remove) 
                contest_question_id = RealityETH.askQuestion("should we delist ArbitratorA?", arbitrator=L2ForkArbitrator)
    Charlie L2.RealityETH.submitAnswer(contest_question_id, 1, value=2000000)
    Charlie L2.AdjudicationFrameworkRequests.freezeArbitrator(contest_question_id, ...)
                    RealityETH.getBestAnswer(contest_question_id)
                    RealityETH.getBond(contest_question_id)
            (or if someone else added an answer provide the history and then do)
                    RealityETH.isHistoryOfUnfinalizedQuestionValid(contest_question_id, ...)
```

NB An AdjudicationFrameworkFeed could do something different here.

#### Next step:

 * Delist question finalizes as 1? [Execute an arbitrator removal](#execute-an-arbitrator-removal)
 * Delist question finalizes as 0? [Cancel an arbitrator removal](#cancel-an-arbitrator-removal)
 * May be contested: [Challenge an arbitrator addition or removal](#challenge-an-arbitrator-addition-or-removal)

### Cancel an arbitrator removal
```
   Bob     L2.ForkingManager.clearFailedProposition(contest_question_id)
                    RealityETH.resultFor(contest_question_id)

```

### Execute an arbitrator removal
```
    Charlie L2.AdjudicationFrameworkRequests.executeModificationArbitratorFromAllowList(contest_question_id)
                    RealityETH.resultFor(contest_question_id)
```
#### Next step:
 * [Handle an arbitration](#handle-an-arbitration) to arbitrate the question again with a different arbitrator

### Propose an arbitrator addition
```
    Charlie L2.AdjudicationFrameworkRequests.requestModificationOfArbitrators(0, ArbitratorA) 
                    contest_question_id = RealityETH.askQuestion("should we add ArbitratorA to AdjudicationFrameworkRequests?")
    Charlie L2.RealityETH.submitAnswer(contest_question_id, 1, value=2000000)
```
#### Next step:
 * [Execute an arbitrator addition](#execute-an-arbitrator-addition) if it finalizes as 1
 * Nothing to do if it finalizes as 0
 * May be escalated to [Challenge an arbitrator addition or removal](#challenge-an-arbitrator-addition-or-removal) and create a fork

### Execute  an arbitrator addition
```
    Charlie L2.ForkArbitrator.executeModificationArbitratorFromAllowList(add_question_id) 
                    RealityETH.resultFor(add_question_id)

```

### Challenge an arbitrator addition or removal
```
    Bob     L2.L2ForkArbitrator.requestArbitration(contest_question_id, uint256 max_previous, ...)
                    # Marks this question done and freezes everything else
                    L2.RealityETH.notifyOfArbitrationRequest(contest_question_id, msg.sender, max_previous, value=999999);

            # Optionally the L2ForkArbitrator waits for a delay specified by the AdjudicationFramework

    [any]  L2.L2ForkArbitrator.requestActivateFork(...)
                    AdjudicationFrameworkRequests.getInvestigationDelay() # Check the delay has passed 
                    ChainInfo.getForkFee() # Make sure the fee is high enough
                    # Calculates a moneyBox address of a contract representing this contract asking about this question
                    BridgeFromL2.bridgeAsset(forkFee, moneyBox)
```

#### Next step
 * [Execute an L2-created fork](#execute-an-l2-created-fork) or [Refund a failed L2-created fork attempt](#refund-a-failed-l2-created-fork-attempt)

### Execute an L2-created fork

```
    [any]  L1.ForkableBridge.claimAsset(...)

    [any]  L1.L1GlobalForkRequester.handlePayment(...)
                    L1.ForkonomicToken.transferFrom(moneyBox, this)
                    L1.ForkonomicToken.approve(forkManager)
                    L1.forkManager.initiateFork(...)
                            L1.ForkonomicToken.transferFrom(L1GlobalForkRequester, fee)
                            # Assign the Chain ID for each chain
                            ChainIdManager.getNextUsableChainId() 
                            ChainIdManager.getNextUsableChainId()
                    # TODO: createIncentivizedMarket() 

    [any]   L1.ForkingManager.executeFork()
                    L1.ForkableBridge.createChildren()
                    L1.ForkableZkEVM.createChildren()
                    L1.ForkableGlobalExitRoot.createChildren()
                    L1.ForkonomicToken.createChildren()
                    # creates own children

    [any]   L1.ForkableBridge.sendForkonomicTokensToChild() # send your own tokens to the child
                child1.mintForkableToken()
                child2.mintForkableToken()

    [hard asset manager]   L1.ForkableBridge.transferHardAssetsToChild()


```

### Refund a failed L2-created fork attempt

If another fork has been started simultaneously or the fee was too low, the fork may not be possible. In that case we unwind the request.

```
    [any]  L1.ForkableBridge.claimAsset(...)

    [any]  L1.L1GlobalForkRequester.handlePayment(...)
                    L1.returnTokens(...)
                    L1.ForkableBridge.bridgeAsset(L2.L2ForkArbitrator)
                    L1.ForkableBridge.bridgeMessage(L2.L2ForkArbitrator, ...)
 
    [any]  
            L2.ForkableBridge.claimAsset()
            L2.ForkableBridge.claimMessage()
                    L2.L2ForkArbitrator.onMessageReceived()
                    L2.RealityETH.cancelArbitration()

    [Bob]   L2.L2ForkArbitrator.claimRefund() # Transfers native token back

```

#### Next step

 * Wait for the fork date, then anyone can [Execute an arbitrator removal](#execute-an-arbitrator-removal) on one chain and [Cancel an arbitrator removal](#cancel-an-arbitrator-removal) on the other.


### Bid in the auction 

TODO: Build this

```
    Bob    L2.IncentivizedMarket.bid(uint256 yes_price_percent, value=tokens)
                burns own tokens
                fork.mint(msg.sender, tokens)

                Wait 1 week
                IncentivizedMarket.calculateClearingPrice()

           L2.IncentivizedMarket.getYesNo(bob)
                withdraw()
                check clearing price
                decide which side the user is on by whether their price is above or below the clearing percent
                give them tokens, multiplied by inverse of clearing percent

#### Need to build:

 * Move burned funds into two pools on L1
 * Sell the burned funds in return for token A or token B on a curve
 * See which has the most tokens unsold, that one is more valuable
 * eg 10000 F1+F2 split into 10000 F1 and 10000 F2
 * First F1 sells for 0.01 ETH
 * Second F1 sells for 0.02 ETH


```

### Propose a contract upgrade
```
    Charlie L1.ForkableRollupGovernor.beginProposition
                    upgrade_question_id = RealityETH.askQuestion("should we execute the bytecode XYZ against contract ABC?")

    Charlie L1.GovToken.approve(RealityETH, 2000000)
    Charlie L1.RealityETH.submitAnswer(upgrade_question_id, 1, 2000000)
```

#### Next step:

 * Upgrade question finalizes as 1? [Execute a contract upgrade](#execute-a-contract-upgrade)
 * Upgrade question finalizes as 0? No need to do anything
 * May be contested: [Challenge a contract upgrade](#challenge-a-contract-upgrade)

### Execute a contract upgrade
```
    Charlie L1.ForkableRollupGovernor.executeProposition(upgrade_question_id, to, bytecode) 
                RealityETH.resultFor(upgrade_question_id)
                call(to, bytecode)
    (TODO: Handle freezing of bridges etc if the proposition is urgent and there is a high bond to that effect)
```

### Challenge a contract upgrade
```
    Bob     L1.GovToken.approve(L1ForkArbitrator, fork_fee)
            L1.L1ForkArbitrator.requestArbitration(upgrade_question_id, ...)
                    // Marks this question done and freezes everything else
                    L2.RealityETH.notifyOfArbitrationRequest(contest_question_id, msg.sender, max_previous, value=999999);
                    L2.ForkingManager.initiateFork()

                    // TODO: This might need a getInvestigationDelay()

    [any]   L1.ForkingManager.executeFork()
                    L1.ForkableBridge.createChildren()
                    L1.ForkableZkEVM.createChildren()
                    L1.ForkableGlobalExitRoot.createChildren()
                    L1.ForkonomicToken.createChildren()
                    L1.ForkableRealityETH_ERC20.createChildren() // TODO, may rethink

    [any]   L1.L1ForkArbitrator.settleChildren()
                    L1.ForkableRealityETH_ERC20-1.assignWinnerAndSubmitAnswerByArbitrator(1)
                    L1.ForkableRealityETH_ERC20-2.assignWinnerAndSubmitAnswerByArbitrator(0)
```

#### Next step

 * [Execute a contract upgrade](#execute-a-contract-upgrade) on one fork.
 * [Import a reality.eth question after a fork](#import-a-reality.eth-question-after-a-fork) for any question we didn't fork over

### Import a reality.eth question after a fork

If an upgrade proposition had been made in parallel when a fork was triggered, it is in a frozen state.
It can be imported to continue the resolution process.
If there are unclaimed funds their questions also need to be imported.

```
    Alice   L1.ForkableRealityETH_ERC20-1.importQuestion(question_id)
    Alice   L1.ForkableRealityETH_ERC20-2.importQuestion(question_id)
```

### Moving gov tokens L2->L1
```
    Alice   L2.Bridge.bridgeAsset(value=123)

    Alice   L1.ForkableBridge.claimAsset() # mints erc20 value
               L1.GovToken.mint(123)
```

### Moving gov tokens L1->L2
```
    Alice   L1.ForkableBridge
                GovToken.approve(L2.Bridge, 123)
                L2.Bridge.bridgeAsset(123) [checks to make sure we're not already forked]

    Alice   L2.Bridge.claimAsset() 
```

### Moving L2-native ERC20 tokens L2->L1
```
    Alice   L2.L2TokenX.approve(L2.Bridge, 123)
            L2.Bridge.bridgeAsset(L2TokenX, 123)

    Alice   L2.ForkableBridge.claimAsset() # 
                L1.L2TokenX.mint(Alice, 123) 
```

### Moving L2-native ERC20 tokens L1->L2
```
    Alice   L1.L2TokenX.approve(L2.Bridge, 123)
            L1.ForkableBridge.bridgeAsset(L2TokenX, 123) [ checks to make sure we're not already forked ]

    Alice   L2.Bridge.claimAsset()
                L2.L2TokenX.mint(Alice, 123) 
```

### Moving L1-native tokens (ETH) L1->L2
```
    Alice   L1.ForkableBridge.bridgeAsset(L1TokenX, value=123)

    Alice   L2.Bridge.claimAsset()
                L2.L1TokenX.mint(Alice, 123)

```

### Moving L1-native tokens (ETH) L2->L1
```
    Alice   L2.L1TokenX.approve(L2.ForkableBridge, 123)
            L2.ForkableBridge.bridgeAsset(L1TokenX, 123)

    Alice   L2.Bridge.claimAsset() TODO: Check this part
                L1.L1TokenX.mint()

```
