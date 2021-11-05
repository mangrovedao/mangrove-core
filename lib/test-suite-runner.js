// Runner for the JS test suites: ./test/test-<suite name>.js
//
// We use this runner instead of Mocha's and Hardhat's runners in order to
// ensure that the right configuration is loaded for the chosen network.
const argv = require("yargs")
  .usage("Usage: $0 --network <network> [testSuite1 ...]")
  .option("network", {
    alias: "n",
    demandOption: true,
    describe: "the network to run the suite against (ethereum, polygon, ...)",
    type: "string",
  })
  .help().argv;

process.env["NODE_APP_INSTANCE"] = argv.network + "-mainnet";

require("app-module-path").addPath(__dirname + "/..");
require("dotenv-flow").config({ silent: true }); // Reads local environment variables from .env*.local files
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/../config/";
}
const config = require("config");
const hre = require("hardhat");
const Mocha = require("mocha");
const fs = require("fs");

const main = async () => {
  await hre.run("compile");

  const mocha = new Mocha(config.mocha);

  var testSuites = argv._;
  if (testSuites.length == 0) {
    const testSuiteFiles = fs
      .readdirSync("./test")
      .filter(
        (file) => file.substr(-3) === ".js" && file.substr(0, 5) === "test-"
      );
    testSuites = testSuiteFiles.map((file) =>
      file.substring(5, file.length - 3)
    );
  }
  console.log(`Running all test suites: ${testSuites}`);
  console.log(`  on network: ${argv.network}`);

  testSuites.forEach((testSuite) =>
    mocha.addFile(`./test/test-${testSuite}.js`)
  );

  mocha.run(function (failures) {
    process.exitCode = failures ? 1 : 0; // exit with non-zero status if there were failures
  });
};

main();
