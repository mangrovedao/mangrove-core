const hre = require("hardhat");

function getProvider() {
  const url = hre.network.config.url;
  return new hre.ethers.providers.JsonRpcProvider(url);
}

function addressOfToken(env, tokenName) {
  function tryGet(cfg, name) {
    if (cfg.has(name)) {
      return cfg.get(name);
    }
  }
  const tkCfg = tryGet(env, `tokens.${tokenName}`);
  return tryGet(tkCfg, "address");
}

function contractOfToken(env, tokenName) {
  const tkAddr = addressOfToken(env, tokenName);
  const tkAbi = require(tryGet(tkCfg, "abi"));
  const provider = getProvider();
  return new ethers.Contract(tkAddr, tkAbi, provider);
}

function getCurrentNetworkEnv() {
  const config = require("config");
  let env = {};
  if (config.has("network")) {
    env = config.get("network");
  } else {
    console.warn("No configuration found for current network");
  }
  return env;
}

exports.getCurrentNetworkEnv = getCurrentNetworkEnv;
exports.contractOfToken = contractOfToken;
exports.addressOfToken = addressOfToken;
exports.getProvider = getProvider;
