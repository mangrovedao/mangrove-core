// Config file with defaults
var config = {};

var defer = require("config/defer").deferConfig;

///////////////////////////
// Hardhat configuration //
/* to test deployments, make the hardhat network emulate another network & reuse 
   the deployment addresses in `accounts` so they are funded:
   hardhat {
     ...
      chainId: 80001,
      accounts: [{privateKey: process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"] || "", balance: "10000000000000000000000"}]
   }
*/

let mumbaiExtraConfig = {
  accounts: [],
};
if (process.env["USE_DEPLOYER_ACCOUNTS"]) {
  if (process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    mumbaiExtraConfig.accounts = [process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]];
  }
}
config.hardhat = {
  defaultNetwork: "hardhat",
  networks: {
    hardhat: {
      gasPrice: 8000000000,
      gasMultiplier: 1,
      blockGasLimit: 7000000000,
      allowUnlimitedContractSize: true,
      //chainId: 31337,
      loggingEnabled: true,
      chainId: 80001,
    },
    mumbai: {
      gasPrice: 30 * 10 ** 9,
      gasMultiplier: 1,
      blockGasLimit: 12000000,
      // add a node url in mangrove-solidity/.env.local
      url: process.env["MUMBAI_NODE_URL"] || "",
      chainId: 80001,
      ...mumbaiExtraConfig,
    },
    localhost: {
      url: "http://127.0.0.1:8545",
    },
  },
  solidity: {
    version: "0.8.10",
    settings: {
      optimizer: {
        enabled: true,
        runs: 20000,
      },
    },
    outputSelection: {
      "*": {
        "*": ["storageLayout"],
      },
    },
  },
  paths: {
    sources: "./contracts",
    tests: "./test",
    cache: "./cache",
    artifacts: "./artifacts",
  },
  abiExporter: {
    path: "./exported-abis",
    runOnCompile: true,
    clear: true,
    flat: true,
    only: [
      ":Mangrove$",
      ":MgvReader$",
      ":MgvCleaner$",
      ":MgvOracle$",
      ":TestMaker$",
      ":TestTokenWithDecimals$",
      ":IERC20$",
      ":MintableERC20BLWithDecimals$",
    ],
    spacing: 2,
    pretty: false,
  },
  testSolidity: {
    logFormatters: require("lib/log_formatters"),
  },
  // see github.com/wighawag/hardhat-deploy#1-namedaccounts-ability-to-name-addresses
  namedAccounts: {
    deployer: {
      default: 1, // take second account as deployer
    },
    maker: {
      default: 2,
    },
    cleaner: {
      default: 3,
    },
    gasUpdater: {
      default: 4,
    },
  },
  mocha: defer(function () {
    // Use same configuration when running Mocha via Hardhat
    return this.mocha;
  }),
};

module.exports = config;
