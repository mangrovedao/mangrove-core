// Config file for Ethereum mainnet tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

////////////////////////////
// Ethereum configuration //
config.ethereum = require("./ethereum/ethereum-mainnet.json");

/////////////////////////
// Mocha configuration //
config.mocha = {
  // Use multiple reporters to output to both stdout and a json file
  reporter: "mocha-multi-reporters",
  reporterOptions: {
    reporterEnabled: "spec, @espendk/json-file-reporter",
    espendkJsonFileReporterReporterOptions: {
      output: "ethereum-mainnet-mocha-test-report.json",
    },
  },
};

///////////////////////////
// Hardhat configuration //
if (!process.env.ETHEREUM_NODE_URL) {
  throw new Error("ETHEREUM_NODE_URL must be set to test Ethereum mainnet");
}
config.hardhat = {
  networks: {
    hardhat: {
      forking: {
        url: process.env.ETHEREUM_NODE_URL,
        blockNumber: 12901866,
      },
    },
  },
};

module.exports = config;
