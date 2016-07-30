# The Reality Token Whitepaper

Edmund Edgar
<ed@realitykeys.com>

2016-04-20, last updated 2016-07-30

# THIS IS A WORK IN PROGRESS. IT IS NOT YET COMPLETE.


## Conceptual Overview 


### Introduction

Blockchain systems provide an effective and well-tested solution for confirming the execution of operations which can be described in computer code. However, the point at which they mesh with the world beyond the blockchain has produced some unique challenges for crypto-economic systems. 

One manifestation of this problem is known as the [Oracle Problem](https://en.bitcoin.it/wiki/Contract#Example_4:_Using_external_state). Smart Contracts often need to reference factual data about the world outside the blockchain on which they reside. If you want to make and settle a contract based on whether it will rain in Tokyo, you ultimately need to know whether it rained in Tokyo. 

A related problem is more commonly represented as a governance issue. Smart contracts are intended to run trustlessly, but in practice they sometimes contain bugs. Dealing with these bugs can range from the need to replace bad contracts with better ones, to the need to reassign assets held by the contract to undo the damage caused by the operation of the bug. In many cases this will prove impossible, or require a change to be applied to the entire underlying system.

Vitalik Buterin coined the term ["subjectivocracy"](https://blog.ethereum.org/2015/02/14/subjectivity-exploitability-tradeoff/) to describe the process by which systems can be allowed to copy themselves to create multiple forks, and users opt into the fork they prefer.

We propose to create a common human-arbitrated subjectivocratic layer on top of the Ethereum blockchain using a shared token which we provisionally call a Reality Token. Using the token allows contracts to access information about the world beyond the blockchain, including factual information and human judgements beyond the domain of code-as-law. This information can be used by contracts outside the subjective layer by observing the relative value the market assigns to the different forks.


### Background: Consensus systems and economic hard forks

Blockchains are designed with the aim that the network should be able to reach agreement on a common ledger, and under normal operation require particular action by participating nodes except for running their software. However, upgrades to blockchain-based consensus systems sometimes involve backwards-incompatible changes, producing "hard forks". If not all participants implement the change, this produces two parallel chains. The chains share a common history, rendering coins spent prior to the fork spendable on both post-fork chains. The two post-fork chains do not recognize each other's transactions, making it possible to spend the same original coins in different ways on each chain.

There is no technical barrier to the creation of incompatible forks. Anyone can attempt to change the rules of a blockchain-based systems. For example, it would be technically straightforward to revise the rules of Bitcoin to increase the issuance of new bitcoins. However, such a change would be ignored by the economic majority: Few people would be interested in transacting on this alternative chain, and nobody would be prepared to trade valuable goods or services in exchange for these coins. The opposite holds for people running forks that reject clearly beneficial changes. For example, when an integer overflow bug was discovered in the Bitcoin that allowed users to award themselves coins, developers forked the system to remove this bug, and coins on the fork that lacked this fix became worthless.

The decision over which fork is more valuable is potentially subjective and may not always have a clear right answer. Opinion may divide semi-permanently, as we saw with the Ethereum DOA fork. However, external information such as the market cap can provide objective facts which, although not necessarily always correct, can be used by outside observers (including contracts residing on the same blockchain) to adjudicate between the branches.


### Reality Tokens: A branch for every possible world anybody cares about

The core of our proposal is the Reality Token contract, which is a contract residing on the Ethereum network.

The Reality Token contract acts like a crypto-currency which potentially undergoes an economic hard fork every day, and tracks all the forked versions in a single data structure. Each fork represents a set of facts about the world. The same coins can be sent to different people on different forks. Forks can be created by anyone at minimal cost, so a fork can exist for any set of facts that anyone wants to claim represents reality. Credits and debits are attached to particular forks, and inherited by all their dependents lower down the chain.

The Reality Token contract has no opinion about which branch really reflects reality. It is therefore never wrong and cannot be manipulated. 

Traditionally, a contract dependent on some outcome such as a betting contract is expected to have a source for the ultimate result. However, a contract denominated in Reality Tokens can settle an outcome simply by sending coins to multiple forks. If Alice bets with Bob that Donald Trump will win the presidential election, competing forks may arise, one claiming that he won and another claiming that he didn't. Rather than attempting to adjudicate this issue, the betting contract can simply pay Alice on the branch that represents Trump winning and pay Bob on the branch that represents Trump losing. The Reality Token contract makes no attempt to choose between between the different branches; It simply allows people to manage how much of the token they would have in each possible world. 

Since coins held on a bogus branch are likely to be worthless and the market will value coins held on the true branch, it is possible to make a functional betting contract without the system ever needing objective confirmation of which branch represents the truth. It is even possible that subsets of users will operate long-lived parallel chains, each with their own self-contained market. For example, religious participants may want to make contracts about acts of divine intervention, which are settled by consensus within their own community, on a branch that they consider valuable but nobody else does.


### The social consensus process

Previous proposals to leverage subjectivocracy on top of existing blockchains have tended to see it as a fall-through layer underneath a process of on-chain voting or coordination games, taking place in a smart contract. Advocating this approach, Buterin [correctly observes](https://blog.ethereum.org/2015/02/14/subjectivity-exploitability-tradeoff/) that "in most practical cases, there are simply far too many decisions to make in order for it to be practical for users to decide which fork they want to be on for every single one".
 
A process is indeed required, and a smart contract may be a good place for it; However, this process does not necessarily need to occur in a smart contract, even less inside a single smart contract decided in advance, or a smart contract necessarily residing on the same blockchain where the information in the contract is used. A set of disparate facts and propositions can be reduced to a set of principles by which these facts and propositions were established, and evidence about whether that process was followed or not.

Social processes by which disparate facts and judgements, many of which are only of interest to a small proportion of participants, can be efficiently arbitrated, are not unique to crypto-currency; Existing judicial systems typically employ multiple tiers, with low-cost social peer-pressure handling the most common cases and increasingly expensive and coercive court systems handling only the cases where each subsequent tier has failed. The trust-based oracle service we have been operating since 2013, [Reality Keys](https://www.realitykeys.com), uses a two-step process where data is first published for inspection, then verified in the event that a fee is paid. Martin Koeppelmann's proposed [Ultimate Oracle](http://forum.groupgnosis.com/t/the-ultimate-oracle/61) operates this way in a decentralized context, with members of a DAO voting only in cases where they think a mistake has been made by a semi-trusted party, and someone believes that the mistake is likely enough to be rectified by a larger voting panel to justify paying a fee. 

Successful systems may also employ coordination games like those proposed by Paul Sztorc in [the TruthCoin whitepaper](http://bitcoinhivemind.com/papers/truthcoin-whitepaper.pdf) and implemented by [Augur](https://www.augur.net/) and [HiveMind](http://bitcoinhivemind.com/). If a single smart contract proves capable of producing efficient and accurate judgements, users may converge on that, and never take any notice of branches published by any other entity. Alternatively, the market may prefer simple, quasi-centralized systems with known publishers of data monitored by their competitors and by users with money at stake. The core requirement, however, is the ability to change it if it proves unsatisfactory.

By leaving the choice of this process to the social sphere rather than baking it into contracts that need to be immutable, we allow insights from this evolving field to be easily incorporated into the overall process, while keeping the core token contract simple and easy to review. 


### Examples of fact arbitration processes


#### Getting the weather in Tokyo

When initially requesting a fact to be sent to a contract, users would specify a URL at which they expected the data would be found, and whether they were prepared to accept an alternative judgement if the URL was no longer functioning correctly.

A data service would access the URL and provide a TLS notary proof of what they found. If the data was missing, on payment of a fee, they would provide their own judgement, which they would publish in a publicly accessible location.

Objections could be lodged in a contract along with payment of a fee, resulting in either a corrected result or a statement that the data published was correct. This could be done either by an individual data provider or by a voting DAO.

The data for the day could be verified by running a script against the notary proofs, and the small number of facts with outstanding objection fees paid could be verified manually.


#### Updating a contract

When deploying a contract, the creator would include in it the hash of a document stored on IPFS specifying under what terms it could be updated. For example, a contract might specify that it could only be updated in the event of a critical bug. 

The document would specify where the new source code for the contract should be published for inspection, and a fee payable to lodge an objection by any party who considered the new contract to be incorrect.

If a sufficient fee was paid, an arbitrator or someone acting on their behalf would review the proposed contract. If no fee was paid, the contract would be assumed correct and its new address accepted.


### An objective view via a decentralized market

We have seen that an application managing assets denominated in Reality Tokens does not need adjudication about which branch is best. However, users of systems denominated external assets may wish to harvest information from the Reality Token system, and reference it in their own contracts. Although there may be no ultimate truth about which branch is correct, it is possible to establish an objective fact about which is considered most valuable. This can be accomplished with a decentralized blockchain-native market allowing holders of coins on different forks to trade them. 

Such a market can be manipulated by spending large sums of money buying coins on a bogus branch. To the extent that one of the correct branches is valuable and the market liquid, such manipulation is likely to be expensive and and ultimately profitable to holders of the legitimate branch, who can sell coins to the manipulator while continuing to hold the coins they sold on other branches. Meanwhile, participants in markets denominated in Reality Tokens are free to ignore the manipulation and continue operating on the branch they consider correct.


### Querying the arbitration layer

Information in the merkel root can be extracted by storing it in an intermediate contract, which can then queried, or by querying the data from an off-chain source such as IPFS and sending the result to an individual contract. 

Each block provides the address of a contract at which the publisher can make information contained in the tree available for contracts to query without the need to provide a Merkel proof. The Reality Token contract does not attempt to verify what information has been published in the suggested contract or whether it matches the contents of the merkel root; This is left to the validation process chosen in the social sphere.

A contract using the token natively would simply request the appropriate data for the branch specified when it was called.

A contract relying on a decentralized market to provide objective guidance to the appropriate branch would first query the market to find the most valuable branch, then request the appropriate data for that branch.


### User interaction

The core requirement of the Reality Token contract is that direct interaction, whether sending funds or querying data, requires that the user specify which branch they want to interact with.

In its crudest form, a betting contract might present a screen to the end user containing a pull-down with a list of available branches. The user would have to consult alternative sources to find out which branch they wanted to transact on. Having done so, they would make bets by sending money to the contract. Then when it came time to claim, they would select a more recent branch, which contained a report on the result of their bet, and claim their payment. In the event that multiple branches appeared valuable and they had won the bet on both branches, they might then also select that other branch and collect their payment on that branch as well.

For most contexts, the user will benefit from assistance from a party or process he trusts in chosing the appropriate branch. This may be a decision-making DAO, a trusted individual, or the judgement of an inter-branch market, or a combination of the above. In some circumstances the software they are using may make this decision for them, and in others it may provide or promote one or more of them as a default.


### The social contract

Many aspects of what would constitute approprate reporting behaviour will be subjective, and potentially controversial. Like existing crypto-currencies, this will depend on a social contract which is partially established at the outset, and partially evolves over time.

The verification of a branch is likely to focus not only on the underlying information reported in it but also on the process by which it is created. Regardless of the content of the information in the branch, unverifiability of the process used to decide on it should be a priori grounds for rejecting a branch in favour of another one. These principles should be further developed in defining the token's initial social contract. 

We propose an initial discussion prior to beginning operation to define the general parameters of the social contract. However, in case of subsequent intractable disagreements the system would sustain multiple competing persistent branches supporting alternative social contracts.


### Our prototype

The Reality Token contract is implemented as a contract on the Ethereum network. To provide time for social mechanisms to alert to incorrect branches, and also to limit the length of each chain and make it possible to traverse a chain without excessive gas use, a new branch can only be added to any given chain once in every 24-hour period. There is no limit to how many competing branches can be created within that 24-hour period, and the system is designed such that adding a competing branch does not result in any additional gas use to a participant unless the participant spends coins on it. Thus the height of the chain is limited to a maximum of one new set of facts per day, but it may have an arbitrary large number of parallel forks.

A new branch point consists of a reference to the previous branch on top of which it builds, and a merkel root representing a merkel tree containing all the facts and judgements about which it makes claims. It is assumed the actual data will be stored elsewhere, and the market will not value a branch whose data is not available. The actual storage location of the data is not managed by the Reality Token contract, although we would suggest either another Ethereum contract, if a high proportion of the data is expected to be needed to be read on-chain, or IPFS, if the need to read the data from the blockchain is unusual.

The set of facts represented by a given merkel root can be arbitrarily large. If it is too large for market participants to verify, we would expect them to prefer an alternative branch that they were able to verify.

Although branches can only be added daily, transfers of tokens down a chain can be made at any time and confirm in the normal Ethereum block interval. 

Transactions are modelled as a credit or debit at a particular fork point. A transaction is only permitted if the account sending it has sufficient credit working back up the chain from the fork point towards the root. Credits and debits can only be added either at the tip of the tree, as you would expect in a normal blockchain system, or at a lower level than the last transaction added by the payer. This restriction allows us to verify that a user has a sufficient balance to make any given payment without considering any credit or debit except the ones from which is directly descended. Since there is only ever one parent block at each height working up the chain from any given point, rather than the infinity of branches that may exist working down the chain, this makes gas costs bounded and predictable.


### Conclusion

By leveraging subjectivocracy we can create a decentralized arbitration layer that can be used in combination with a system executing code-as-law. This allows contracts to opt in to a system of human judgement that shares some of the security properties of the base system, without the need to trust voting process or identified third-parties. The existence of an opt-in hard-forking arbitration layer may also reduce the temptation to rewrite the rules of the base layer by forking the underlying blockchain after the fact.
