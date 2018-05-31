RealityToken
=======


Collection of smart contracts that form the basis of the RealityToken ecosystem.


Audit
-----
### Audit Report:

[To be linked]()


Install
-------
### Install requirements with npm:

```bash
npm install
```

Testing
-------
### Start the TestRPC with bigger funding than usual, which is required for the tests:

```bash
truffle test
```
Please install at least node version >=7 for `async/await` for a correct execution

### Run all tests 

```bash
truffle test -s
```
The flag -s runs the tests in a silence mode. Additionally the flag -g can be added to plot the gas costs per test.


Compile and Deploy
------------------
These commands apply to the RPC provider running on port 8545. You may want to have TestRPC running in the background. They are really wrappers around the [corresponding Truffle commands](http://truffleframework.com/docs/advanced/commands).

### Compile all contracts to obtain ABI and bytecode:

```bash
truffle compile --all
```

### Migrate all contracts:

```bash
truffle migrate --network NETWORK-NAME
```


Documentation
-------------

Please see the attached realitytoken.pdf


Contributors
------------
- Edmund Edgar ([dteiml](https://github.com/edmundedgar))
- Alexander ([josojo](https://github.com/josojo))
