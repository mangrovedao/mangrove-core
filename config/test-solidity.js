// Config file for Solidity tests in test environment
// NB: We are abusing the NODE_APP_INSTANCE env var to make test suite specific configurations.
var config = {};

/////////////////////////
// Mocha configuration //
config.mocha = {
  // Use multiple reporters to output to both stdout and a json file
  reporter: "mocha-multi-reporters",
  reporterOptions: {
    reporterEnabled: "spec, @espendk/json-file-reporter",
    espendkJsonFileReporterReporterOptions: {
      output: "solidity-mocha-test-report.json",
    },
  },
};

module.exports = config;
