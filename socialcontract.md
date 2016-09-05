# Draft Social Contract

Edmund Edgar
<ed@realitykeys.com>

2016-08-30

### This is a work-in-progress. It is not yet complete.


## Aims and scope

The Reality Token system provides infrastructure for attaching payments to a particular bundle of facts and propositions. 

The following draft proposes a set of principles which participants should follow when creating bundles of facts and propositions, or deciding which bundle to treat as valuable.

We have no way to enforce these principles, except to the extent that participants do not consider bundles valuable unless they follow them.


## Principles guiding data providers

### Verifiability

All data added to a bundle should be verifiable by arbitrary participants. Where this requires an automated process, the code for that process should be open source and publicly available.

### Procedural Transparency

The procedure by which a data provider reaches a decision should be stated clearly in advance, and followed as closely as reasonably possible. Where circumstances require a change to the procedure stated originally, this should be clearly explained.

### Non-discriminatory pricing and data access

Providers may charge to include data in a bundle, but these charges should be reasonable, non-discriminatory and stated clearly in advance.

Data should be provided regardless of the use to which it is likely to be put.

### Predictable data access

It should be possible for participants to write contracts in the expectation that a particular piece of data will be available at a particular time. 

This cannot be guaranteed as some data may be difficult or expensive to provide, and providers may cease to make it available. Where this occurs, the bundle should prioritize restoring data access. Restoring predictable access to data may mean compromising on the quality of data provided.


## Principles guiding certainty and reversibility

Even when facts and judgements are made on the best available information, there is always a risk that new information will show previously-published information to be incorrect. Facts and judgements may fall into the following classifications, people requesting information should be clear about which they want:

### Final vs Evolving

An evolving fact may be over-written in a subsequent bundle. A final fact cannot be over-written, and can only be changed by orphaning the bundle that produced it.

TODO: Work through the detail of querying a fact and check we can sanely handle evolving facts.

### Confidence level

The confidence level should be stated as a %, showing how confident a data source must be about a pice of data before they publish it. Depending on needs, data sources may set a policy for a single confidence level and which they release data, or publish multiple items of data at different confidence levels.


## Reverting to earlier forks

Each bundle is added within a defined 24-hour window, starting at 00:00:00 UTC. Participants are encouraged to create rival branches within the defined window, or where necessary within the following window. Where practical, data providers should publish previews of the data they intend to publish in advance.

Although it is technically possible to add a child to any previous bundle, including the initial one, participants should try to avoid reverting more than 3 days. We propose an absolute maximum of 7 days' reversion, allowing participants to make payments with funds that they have held for more than 7 days without worrying that the economic majority may settle on a different branch. If incorrect data or a failure to fulfill the social contract is undetected for 7 days, it should be considered too late to correct it.


## Changing the social contract

If a bundle is provided that intends to change the terms stated above, the data it provides should include the hash of the new social contract, which should be stored where participants can find it.
