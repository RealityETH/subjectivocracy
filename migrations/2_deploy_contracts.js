var ArbitratorList = artifacts.require("./ArbitratorList.sol");
var RealityToken = artifacts.require("./RealityToken.sol");
var ArbitratorData= artifacts.require("./ArbitratorData.sol");
var InitialDistribution= artifacts.require("./Distribution.sol");

const feeForRealityToken = 1000000000000000000

module.exports = function(deployer, network, accounts) {
    deployer.deploy(RealityToken)
}
