const hre = require("hardhat");

function getProvider() {
  const url = hre.network.config.url;
  return new hre.ethers.providers.JsonRpcProvider(url);
}

function tryGet(cfg, name) {
  if (cfg.has(name)) {
    return cfg.get(name);
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

function contractOfToken(tokenName) {
  const env = getCurrentNetworkEnv();
  const tkAddr = tryGet(env, `tokens.${tokenName}.address`);
  const tkAbi = require(tryGet(env, `tokens.${tokenName}.abi`));
  const provider = getProvider();
  return new ethers.Contract(tkAddr, tkAbi, provider);
}

async function getMangrove() {
  const provider = getProvider();
  const mgv = {};
  let main = await hre.ethers.getContract("Mangrove");
  mgv.reader = await hre.ethers.getContract("MgvReader");
  mgv.contract = main;
  return mgv;
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

function getAave() {
  const env = getCurrentNetworkEnv();
  const lendingPoolAddr = tryGet(env, `aave.lendingPoolAddress`);
  const lendingPoolAbi = require(tryGet(env, `aave.lendingPoolAddress`));
  const provider = getProvider();
  return new ethers.Contract(lendingPoolAddr, lendingPoolAbi, provider);
}

function getFaucet(faucetName) {
  const env = getCurrentNetworkEnv();
  const faucetAddr = tryGet(env, `faucets.${faucetName}.address`);
  const faucetAbi = require(tryGet(env, `faucets.${faucetName}.abi`));
  const provider = getProvider();
  return new ethers.Contract(faucetAddr, faucetAbi, provider);
}

exports.sleep = sleep;
exports.getMangrove = getMangrove;
exports.getCurrentNetworkEnv = getCurrentNetworkEnv;
exports.contractOfToken = contractOfToken;
exports.getProvider = getProvider;
exports.getAave = getAave;
exports.getFaucet = getFaucet;
