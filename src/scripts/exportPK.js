var keythereum = require("keythereum");

// Specify a data directory (optional; defaults to ~/.ethereum)
var datadir = "/home/ubuntu/zkevm/zkevm-config";
var file = datadir + "/" + "aggregator.keystore";

var addr = "0x5669c63e3b461cf50696ad0378fe2e66b982d4a7";
// Synchronous
var keyObject = keythereum.importFromFile(addr);

var privateKey = keythereum.recover("password", keyObject);
console.log(privateKey.toString('hex'));

