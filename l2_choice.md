
# Selecting an L2

### Edmund Edgar, 2021-03-24

In [our design](design.md) we described a system for an L2 with an enshrined oracle, and a mechanism on the L1 chain for governing the ledger such that "hard" assets on the L1 chain end up using the appropriate version of the chain.

Here we will discuss the possible design parameters of the L2 system.

## Governance models

We can identify the following models for governance requirements:

### Model A. No governance needed (except oracles)

We can use a reality.eth instance on L2. The fork can deploy automatically-cloned L1 contracts.

### Model B. May need governance for planned upgrades

We can use a reality.eth instance on L2. The design is identical to oracle governance except that it forks over "should we use new contract X", and forks to versions that do and don't do that.

### Model C. May stop and need governance to restart them

We need a forkable reality.eth instance on L1. 

### Model D. May need governance to detect and repair a bad ledger

We need a forkable reality.eth instance on L1. Additionally, payouts on L1 from bridges for L2 assets need to include delays to allow time for the system to detect and respond to bad ledgers.


## Governance models

### Simple PoS chain using Aura consensus

We can run a PoS network like XDai, governed on Model D.

An invalid ledger can immediately be ignored by participants. If validators refuse to create a valid ledger, participants will need to fork to replace them with new validators. To do this, they need to agree a block number and a new list of validators, and add that to their genesis.json. They then need an L1 governance proposition to use the new bridge.

An invalid bridge output can be detected by users, and a new bridge substituted by the L1 governance process. Since there are no guarantees of available L2 data, they will need time to discuss whether the L2 data is unavailable - they can't just run a bot, because if they lose the ability to sync the chain they won't know whether that's the fault of the validators or their own syncing problem.


### Optimism

We can run a custom version of the Optimism ledger.

NB Mainnet contracts are quite expensive to deploy - expect around 30 million gas for the initial deployment, and the same again per fork.

In theory the system should ultimately support model A, however it has a delay for bridged assets as with D. In practice it may need to be handled as Model C or D until matured.


### ZKSync (future release with more contract support)

We can run a custom version of the ZKSync ledger. On-chain contracts seem to be reasonably inexpensive.

In principle the architecture can support anyone performing validation, and should be usable without the need to upgrade. In this state we could turn off governance and only handle oracles. (Model A)

The current version of ZKSync, which deals mainly with payments, seems to have a trusted upgrade process, mitigated by the ability to withdraw. Since the ability to withdraw is not helpful in many cases, we may need to replace this with our own governance process for upgrades. 

If it can support anyone performing validation, but still needs governance, we can do governance with a reality.eth instance on L2. (Model B).

Currently it appears to use validator whitelists, so the best we can do is Model C, or potentially Model D until it matures.

