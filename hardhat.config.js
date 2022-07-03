require("app-module-path/register");
require("hardhat-storage-layout");
require("dotenv-flow").config({ silent: true }); // Reads local environment variables from .env*.local files
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
// Hierachical loading of config/ (see ^^) files (default.js)
const config = require("config"); // Reads configuration files from /config/

require("hardhat-deploy");
require("hardhat-deploy-ethers");

require("./lib/hardhat-mainnet-env.js"); // Adds Ethereum/polygon environment to Hardhat Runtime Envrionment

require("hardhat-contract-sizer");
require("hardhat-preprocessor");
// Use Hardhat configuration from loaded configuration files

module.exports = config.hardhat;
