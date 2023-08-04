## Compilation

Compiled bytecode and ABIs are stored under *bytecode/* and *abi/* respectively. If you need to recompile, do:

`$ cd development/contracts/`

`$ ./compile.py ForkManager`


## Tests

Contract tests use python3.

`python3 -m venv venv`  
`source ./venv/bin/activate`
`$ cd tests/python`
`$ pip install -r requirements.txt`

You can then test the version in question with, eg

`$ python test.py`

These tests test the bytecode not the source code, so you need to recompile before testing source code changes.

If working on the tests, it can be faster to run only the test you are working on and skip the others. To do this, comment out the line 

`@unittest.skipIf(WORKING_ONLY, "Not under construction")`

then run the test with `WORKING_ONLY=1 python test.py`

