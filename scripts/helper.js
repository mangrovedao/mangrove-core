const hre = require("hardhat");
const { ethers } = require("../../mangrove.js/node_modules/ethers/lib");

function getProvider() {
  const url = hre.network.config.url;
  switch (process.env["PROVIDER"]) {
    case "WEBSOCKET":
      return new ethers.providers.WebSocketProvider(network.config.url);
    case "JSONRPC":
      return new ethers.providers.JsonRpcProvider(network.config.url);
    default:
      return new hre.ethers.getDefaultProvider(url);
  }
}

exports.getProvider = getProvider;
