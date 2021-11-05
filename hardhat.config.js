require("app-module-path/register");
require("dotenv-flow").config({ silent: true }); // Reads local environment variables from .env*.local files
if (!process.env["NODE_CONFIG_DIR"]) {
  process.env["NODE_CONFIG_DIR"] = __dirname + "/config/";
}
const config = require("config"); // Reads configuration files from /config/
require("hardhat-deploy");
require("hardhat-deploy-ethers");
require("hardhat-abi-exporter");
require("adhusson-hardhat-solpp");

require("./lib/hardhat-mainnet-env.js"); // Adds Ethereum/polygon environment to Hardhat Runtime Envrionment

require("@giry/hardhat-test-solidity");
// Use Hardhat configuration from loaded configuration files
module.exports = config.hardhat;
