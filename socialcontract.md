# Draft Social Contract

Edmund Edgar
<ed@realitykeys.com>

2016-08-30

### This is a work-in-progress. It is not yet complete.


## Aims and scope

The Reality Token system provides infrastructure for attaching payments to a particular bundle of facts and propositions. 

The following draft proposes a set of principles which participants should follow when creating bundles of facts and propositions, or deciding which bundle to treat as valuable.

These principles are enforced only by the unwillingness of participants to value payments sent to bundles that do not follow them.


## Principles guiding data providers

### Verifiability

All data added to a bundle should be verifiable by arbitrary participants. Where this requires an automated process, the code for that process should be open source and publicly available. Where it requires a human process, the steps involved should be clear in advance, and they should be followed with the greatest practical transparency.

### Procedural Transparency

The procedure by which a data provider reaches a decision should be stated clearly in advance, and followed as closely as reasonably possible. Where circumstances require a change to the procedure stated originally, this should be clearly explained.

### Non-discriminatory pricing and data access

Providers may charge to include data in a bundle, but these charges should be reasonable, non-discriminatory and stated clearly in advance.

Data should be provided regardless of the use to which it is likely to be put.

### Predictable data access

It should be possible for participants to write contracts in the expectation that a particular piece of data will be available at a particular time. 

This cannot be guaranteed as some data may be difficult or expensive to provide, and providers may cease to make it available. Where this occurs, the bundle should prioritize restoring data access. Restoring predictable access to data may mean compromising on the quality of data provided.


### Accepting new sources of data

Data should be accepted inclusively into bundles, as long as the organization, individual or DAO supplying it satisfies the requirements specified in this document.


## Principles guiding certainty and reversibility

Even when facts and judgements are made on the best available information, there is always a risk that new information will show previously-published information to be incorrect. Facts and judgements may fall into the following classifications, people requesting information should be clear about which they want:

### Final vs Evolving

An evolving fact may be over-written in a subsequent bundle. A final fact cannot be over-written, and can only be changed by orphaning the bundle that produced it.

TODO: Work through the detail of querying a fact and check we can sanely handle evolving facts.

### Confidence level

The confidence level should be stated as a %, showing how confident a data source must be about a piece of data before they publish it. Depending on needs, data sources may set a policy for a single confidence level and which they release data, or publish multiple items of data at different confidence levels.


## Reverting to earlier forks

Each bundle is added within a defined 24-hour window, starting at 00:00:00 UTC. Participants are encouraged to create rival branches within the defined window, or where necessary within the following window. Where practical, data providers should publish previews of the data they intend to publish in advance.

Although it is technically possible to add a child to any previous bundle, including the initial one, the process of verifying a bundle and replacing it if necessary should be completed within 3 days where reasonably possible. 

7 days' reversion should be considered an absolute maximum: If incorrect data or a failure to fulfill the social contract is undetected for 7 days, it should be considered too late to correct it.

Note that this restriction is not enforced at a technical level, as it could trivially be avoided by adding dummy bundles to intermediate windows.


## Changing the social contract

If a bundle is provided that intends to change the terms stated above, the data it provides should include the hash of the new social contract, which should be stored where participants can find it.
