# Hard-forking every day for fun and profit

## Dumb smart contracts

There is a school of thought that says that smart contracts are [mostly pointless](http://www.coindesk.com/three-smart-contract-misconceptions/). Most interesting contracts depend on some outside event happening in the real world: A stock price going up or down, a football game won or lost, an earthquake in Tokyo happening or not happening, 

Blockchains have no knowledge of reality. They do not know what happened to Apple stock, unless that stock is actually being traded on the blockchain. They do not know won a football game, or even what a football game is. They have no idea whether Tokyo is still standing.

In practice we have tended to rely on trusted authorities to solve these problems. I started [Reality Keys](https://www.realitykeys.com/) in 2013 to make some of these uses possible, and we are seeing some great services built on top of it, such as the pioneering decentralized exchange [EtherDelta](https://etherdelta.github.io/). But many people are justifiably unsatisfied with relying on reputation: We use decentralized systems because we want to avoid being reliant on trusted parties. As Nick Szabo observes, [trusted third parties are security holes](http://szabo.best.vwh.net/ttps.html).

The inability for blockchain to apply judgement shows in other places, too. It is difficult for smart contract developers to be confident that their contracts are correct. Many developers have responded by reintroducing developer back-doors, which brings back the trusted third party. Others, like The DAO, coded update procedures into the smart contracts themselves. [This has not always worked out well](http://www.coindesk.com/dao-attacked-code-issue-leads-60-million-ether-theft/).


## Fork this

But recently people were surprised to discover that our solidity code wasn't really trapped in the judgement-free box. When The DAO was hacked, it turned out that there was an escape route. The smart contract code is can't make judgements, but the people running the code can. Users of Ethereum believed they could tell the difference between a hack and the intended operation of the code, and they forked Ethereum to match their judgement.

Bringing judgements about human reality into the operation of the blockchain was, unsurprisingly, controversial. A lot of users thought that the entire point of the blockchain was to be able to create a world where Code Is Law. Some people asked, if that world can be altered by human judgement at any time, what is the point of creating the blockchain in the first place?

What we saw at the same time, however, is that the world of economic hard forks provides kind of security that nothing else in crypto-currency can match. People who saw the DAO fork as an abuse, rather than a correction, simply carried on using their own preferred version. The hard fork provides the ultimate in censorship-proofing: Even with minority hashpower, ETC users are able to trade and transact according to the ledger that they think is correct.

Interaction with the world of human judgement is often useful, but inserting human judgement into the actions of blockchains is something we'd rather avoid. So what if we could the best of both worlds? By using the ability of humans to select a fork, we can build a human judgement layer on top of the machine layer. *That* layer can be forked, while leaving the underlying code-is-law layer alone. So let's fork it. Every day.


## A hard fork every day

Our proposal is explained in detail in [our whitepaper](https://github.com/realitykeys/subjectivocracy/blob/master/whitepaper.md). But here's how it works in outline: Where a normal blockchain consists of bundles of transactions chained together into blocks, we instead chain together bundles of facts and judgements. Every day anybody can create a bundle of information add it to the bottom of an existing branch. Then we leave the world to decide whether it wants to use it or not.

When they hear that we intend to hard-fork every day, a lot of people imagine an unfathomable chaos of branches. But that is not what we see in the real world. Git makes software branching cheap and anyone can make their own version, yet we don't usually have trouble working out which software to use. When we do have a hard time deciding, it's a choice between a small number of alternatives that have emerged with a fundamentally different governance model or design choice.

We don't need to specify what process people will use to choose a branch. Indeed, this is something we should *not* specify. There are all kinds of possible solutions that may be adopted at any given time: Voting DAOs, coordination games, following a respected friend, trusting the person who distributes your software, copying today's recommended branch from the New York Times. You can also take the most valuable branch on a decentralized market, which we will come to in a moment. 

Some of these strategies are only starting to be tried in practice; [Augur](https://www.augur.net/), based loosely on [Paul Sztorc's Truthcoin design](http://bitcoinhivemind.com/papers/truthcoin-whitepaper.pdf), uses coordination games and tries to reward truth-tellers and punish liars. Gnosis propose a voting DAO, taking the role of an [Ultimate Oracle](http://forum.groupgnosis.com/t/the-ultimate-oracle/61) that can resolve provide backing for a trust-based system.

All of these strategies can be manipulated or exploited if you're prepared to throw enough money at it. But no amount of money can prevent people from trading with each other on the fork that they consider best.


## Every possible world that anybody cares about, in a single contract

We provide [a token contract](https://github.com/realitykeys/subjectivocracy/blob/master/contracts/realitytoken.sol) that manages an infinity of forking paths, each representing a different reality. In each possible world, the contract knows how much of the token you have, and enforces how much you can spend. It lives on top of Ethereum, and it can move money between around as fast as Ethereum can. Creating a fork is cheap, like creating a branch in Git, so anybody can create their version of reality, then see if they can persuade other people to live and transact in that reality with them.

Once we can put different realities in different forks, smart contracts no longer need to choose between them. If you want to make a bet on whether Hillary Clinton beat Donald Trump, you no longer need an objective source of truth about whether Hillary Clinton beat Donald Trump. You simply pay the person who bet on Hillary on the branch that things Hillary won, and the person who bet on Trump on the branch that thinks Trump won. If it was Hillary Clinton who won, the tokens on a fork that says she lost probably won't be very valuable; But that's not something your contract needs to worry about.

Sometimes, as we saw with ETC vs ETH, there are fundamental disagreements that prevent people working together in the same reality. The same probably goes for a system of judgements and truths. If religious participants want to bet on divine intervention and settle some of the bets as miracles, they're welcome to do that on their own branch. They don't need to bother the rest of us.


## Decentralized markets: (exploitable) objective truth for everybody else

Like a branch of bitcoin that makes more than 21 million bitcoins, some forks are worthless. The purpose of this token is to provide correct information, so a fork of that token full of bogus information is equally worthless. The same is true of a fork of that token whose correctness cannot be verified - for example, because it contains a large amount of information, but no clear process was followed in putting that information together. 

Although there is no objective way for a contract to know which branch is true, a contract *is* able to check which contract is the most valuable. If the branches to be traded on a decentralized market, a contract can query that market to find which branch is valued the highest, and assume that this branch is correct. At a price, these markets can be manipulated. The more valuable the token and the more liquid the market, the more expensive the markets will be to rig. As far as people holding the token are concerned, they're welcome to try: Everyone holds tokens on the manipulated branches, and they will be happy to sell them to the manipulator.


## Making it happen

Once smart contracts can interact trustlessly with reality, they become incredibly useful. Here's what we need to do to make this happen.

* Discuss the initial social contract with a set of principles for what people should consider when they decide what is a good branch and what isn't.
* Make a prototype Governance DAO contract to recommend which forks to use.
* Review and improve the prototype token contract
* Deploy the contract on a chain, with some method of distributing the initial tokens.
* Start publishing daily bundles of facts and judgements. Reality Keys can do this if nobody else does.
* Tell people about the contract.
* Make some applications that use the token, tell people about them and start using them
* If people are depending on a single daily bundle, break it on purpose without warning to see if they can fix it
* Build an inter-branch market allowing people to query the most valuable branch and milk it for "objective" truth

We need some help getting this done. Come and talk to us on our Gitter channel.



### Acknowledgements: 

* Vitalik Buterin explains the theoretical foundation for "subjectivocracy" at length 
https://blog.ethereum.org/2014/11/25/proof-stake-learned-love-weak-subjectivity/
https://blog.ethereum.org/2015/02/14/subjectivity-exploitability-tradeoff/
* Paul Sztorc and TruthCoin
* Augur
* Martin Koppelmann's Ultimate Oracle provides a clear road-map to scaling 
