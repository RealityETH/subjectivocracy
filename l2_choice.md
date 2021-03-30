
# Selecting an L2

### Edmund Edgar, 2021-03-24

In [our design](design.md) we described a system for an L2 with an enshrined oracle, and a mechanism on the L1 chain for governing the ledger such that "hard" assets on the L1 chain end up using the appropriate version of the chain.

Here we will discuss the possible design parameters of the L2 system.

Different systems may or may not publish the following on-chain:

 * Bridge output
 * State roots allowing for validity proofs
 * Transaction data proving that data needed for validity proofs is available
 * Transactions that may otherwise be censored by L2 block constructors

We can identify the following models for governance requirements:

## Model A. No governance needed (except oracles)

We can use a reality.eth instance on L2. The fork can deploy automatically-cloned L1 contracts.

## Model B. May need governance for planned upgrades

We can use a reality.eth instance on L2. The design is identical to oracle governance except that it forks over "should we use new contract X", and forks to versions that do and don't do that.

## Model C. May stop and need governance to restart them

We need a forkable reality.eth instance on L1. 

## Model D. May need governance to detect and repair a bad ledger

We need a forkable reality.eth instance on L1. Additionally, payouts on L1 from bridges for L2 assets need to include delays to allow time for the system to detect and respond to bad ledgers.



Options

## Simple PoS chain using Aura consensus

We can run a PoS network like XDai.

An invalid ledger can immediately be ignored by participants. If validators refuse to create a valid ledger, participants will need to fork to replace them with new validators. To do this, they need to agree a block number and a new list of validators, and add that to their genesis.json. They then need an L1 governance proposition to use the new bridge.

An invalid bridge output can be detected by users, and a new bridge substituted by the L1 governance process. Since there are no guarantees of available L2 data, they will need time to discuss whether the L2 data is unavailable - they can't just run a bot, because if they lose the ability to sync the chain they won't know whether that's the fault of the validators or their own syncing problem.

Since the bridge has a delay in the L2->L1 direction, it may be useful to use other methods to swap assets.


## Optimism

We can run a custom version of the Optimism ledger.

NB Mainnet contracts are quite expensive to deploy - expect around 30 million gas for the initial deployment, and the same again per fork.

In theory the system should ultimately support model A, however it has a delay for bridged assets as with D. In practice it may need to be handled as model C until matured.


## ZKSync

We can run a custom version of the ZKSync ledger. On-chain contracts seem to be reasonably inexpensive.

The current version of ZKSync, which deals mainly with payments, seems to have a trusted upgrade process, mitigated by the ability to withdraw. Since the ability to withdraw is not helpful in many cases, we may need to replace this with our own governance process for upgrades. 

In principle the architecture can support anyone performing validation, and should be usable without the need to upgrade. In this state we could turn off governance and only handle oracles. (Model A)

If it can support anyone performing validation, but still needs governance, we can do governance with a reality.eth instance on L2. (Model B).

Currently it appears to use validator whitelists, so the best we can do is Model C.




Notes dump

  - If controversy, go to arbitration. Forking the 2 ledgers still works. 
    - Issue: Also need to fork reality.eth? People should get paid on their respective branches in their respective versions of the token
      Subjective way:
        - Single-use reality.eth, only used for 1 fork
        - Make a new L1 reality.eth, assign its balance to the new token
        - Need new constructor with ability to clone a question?
           - Issue: Commitments make this complicated as they're infinitely long, remove them
          or
        - Function to register the question with the new instance based on reading the previous instance
            need to make question IDs unique per reality.eth instance
            new variable for parent
            migrateQuestion() reads question data from parent and registers it
            could be in fork manager, question needs to be migrated before it's released from arbitration
          or 
        - Claim function using only history hash
      Notify arbitration request locks preventing new questions
      Winner way:
        - Single result of the governance process, people putting up bonds on the losing side will lose
  - Issue: We can only do one goverance challenge at a time, is that OK? 
  



TODO: What's the relationship between the signers of the PoS chain and the signers of the bridge transactions?


Optimism 

 * Everything about the chain operation is verifiable on L1.
 * The tech isn't ready to be run without governance.
 * Forking Optimism is expensive because a lot of contracts need to be deployed.
     Looks like about 30 million gas for the entire set
     TODO: Do we need all of them or can some be reused?

  Issue: What does it look like to say "we fork from block 123"
   - challenges may cover that period?

Issue
 - If validators sign a bad ledger, someone immediately forks to a new ledger with new validators
 - Invalid block should quickly be forked around
   - Issue: How do you change a clique signer group
 - Bridge may already have handled transactions from a chain that turned out to be bad
  - Make signers to the bridge put up collateral
  - Delay bridge transactions for long enough to get straight, like optimism

- Bridge conists of signers (or different set of signers) signing a set of transactions, can probably model on amb bridge
