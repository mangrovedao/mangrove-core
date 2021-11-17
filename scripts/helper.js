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
  try {
    // trying to see whether Mangrove is part of current deployment
    let main = await hre.ethers.getContract("Mangrove");
    const deployer = (await provider.listAccounts())[0];
    main = main.connect(provider.getSigner(deployer));
    mgv.reader = await hre.ethers.getContract("MgvReader");
    mgv.contract = main;
    return mgv;
  } catch (error) {
    // otherwise fetches Mangrove in the static addresses of the network config
    const env = getCurrentNetworkEnv();
    const mgvCfg = tryGet(env, "mangrove");
    const mgvAbi = require(tryGet(mgvCfg, "abis.main"));
    const mgvAddr = tryGet(mgvCfg, "addresses.contracts.main");
    const readerAbi = require(tryGet(mgvCfg, "abis.reader"));
    const readerAddr = tryGet(mgvCfg, "addresses.contracts.reader");
    let main = new ethers.Contract(mgvAddr, mgvAbi, provider);
    const reader = new ethers.Contract(readerAddr, readerAbi, provider);

    const key = hre.config.networks[env.network].accounts[0];
    const signer = new ethers.Wallet(key, provider);
    const deployer = tryGet(mgvCfg, "addresses.deployers.main");
    const addr = await signer.getAddress();
    //sanity check
    if (addr != deployer) {
      console.error("Invalid deployer key/address");
      return;
    }
    main = main.connect(signer);
    mgv.contract = main;
    mgv.reader = reader;
    return mgv;
  }
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

exports.getMangrove = getMangrove;
exports.getCurrentNetworkEnv = getCurrentNetworkEnv;
exports.contractOfToken = contractOfToken;
exports.getProvider = getProvider;
