const config = require("config");

module.exports = (ethers) => {
  let mainnetConfig;
  let networkName;

  if (config.has("ethereum")) {
    mainnetConfig = config.get("ethereum");
    networkName = "ethereum";
  }

  if (config.has("polygon")) {
    mainnetConfig = config.get("polygon");
    networkName = "polygon";
  }

  // if no network name is defined, then one is not forking mainnet
  if (!networkName) {
    return;
  }

  let env = {};

  env.mainnet = {
    network: mainnetConfig.network,
    name: networkName,
    tokens: getConfiguredTokens(mainnetConfig, networkName, ethers),
    abis: getExtraAbis(mainnetConfig),
  };

  const childChainManager = getChildChainManager(mainnetConfig);
  if (childChainManager) {
    env.mainnet.childChainManager = childChainManager;
  }

  const mangrove = tryGetMangroveEnv(mainnetConfig, networkName, ethers);
  if (mangrove) {
    env.mainnet.mgv = mangrove;
  }

  const compound = tryGetCompoundEnv(mainnetConfig, networkName, ethers);
  if (compound) {
    env.mainnet.compound = compound;
  }

  const aave = tryGetAaveEnv(mainnetConfig, networkName, ethers);
  if (aave) {
    env.mainnet.aave = aave;
  }

  return env;
};

function getChildChainManager(mainnetConfig) {
  if (mainnetConfig.has("ChildChainManager")) {
    return mainnetConfig.get("ChildChainManager");
  }
}

function getExtraAbis(mainnetConfig) {
  let abis = {};
  if (mainnetConfig.has("extraAbis")) {
    abis.stableDebtToken = require(mainnetConfig.get(
      "extraAbis.stableDebtToken"
    ));
    abis.variableDebtToken = require(mainnetConfig.get(
      "extraAbis.variableDebtToken"
    ));
    abis.aToken = require(mainnetConfig.get("extraAbis.aToken"));
  }
  return abis;
}

function getConfiguredTokens(mainnetConfig, networkName, ethers) {
  let tokens = {};

  if (!mainnetConfig) {
    console.warn(
      `No network configuration was loaded, cannot fork ${networkName} mainnet`
    );
    return;
  }

  // DAI
  if (mainnetConfig.has("tokens.dai")) {
    const daiContract = tryCreateTokenContract(
      "DAI",
      "dai",
      mainnetConfig,
      networkName,
      ethers
    );
    if (daiContract) {
      tokens.dai = { contract: daiContract };

      const daiConfig = mainnetConfig.get("tokens.dai");
      if (daiConfig.has("adminAddress")) {
        tokens.dai.admin = daiConfig.get("adminAddress"); // to mint fresh DAIs on ethereum
      }
    }
  }

  // USDC
  if (mainnetConfig.has("tokens.usdc")) {
    const usdcContract = tryCreateTokenContract(
      "USDC",
      "usdc",
      mainnetConfig,
      networkName,
      ethers
    );
    if (usdcContract) {
      tokens.usdc = { contract: usdcContract };

      const usdcConfig = mainnetConfig.get("tokens.usdc");
      if (usdcConfig.has("masterMinterAddress")) {
        tokens.usdc.masterMinter = usdcConfig.get("masterMinterAddress"); // to give mint allowance
      }
    }
  }

  // WETH
  if (mainnetConfig.has("tokens.wEth")) {
    const wEthContract = tryCreateTokenContract(
      "WETH",
      "wEth",
      mainnetConfig,
      networkName,
      ethers
    );
    if (wEthContract) {
      tokens.wEth = { contract: wEthContract };
    }
  }

  // Compound tokens
  // CDAI
  if (mainnetConfig.has("tokens.cDai")) {
    const cDaiContract = tryCreateTokenContract(
      "CDAI",
      "cDai",
      mainnetConfig,
      networkName,
      ethers
    );
    if (cDaiContract) {
      tokens.cDai = {
        contract: cDaiContract,
        isCompoundToken: true,
      };
    }
  }
  // CUSDC
  if (mainnetConfig.has("tokens.cUsdc")) {
    const cUsdcContract = tryCreateTokenContract(
      "CUSDC",
      "cUsdc",
      mainnetConfig,
      networkName,
      ethers
    );
    if (cUsdcContract) {
      tokens.cUsdc = {
        contract: cUsdcContract,
        isCompoundToken: true,
      };
    }
  }

  // CETH
  if (mainnetConfig.has("tokens.cwEth")) {
    const cEthContract = tryCreateTokenContract(
      "CWETH",
      "cwEth",
      mainnetConfig,
      networkName,
      ethers
    );
    if (cEthContract) {
      tokens.cwEth = {
        contract: cEthContract,
        isCompoundToken: true,
      };
    }
  }

  return tokens;
}

function tryCreateTokenContract(
  tokenName,
  configName,
  mainnetConfig,
  networkName,
  ethers
) {
  if (!mainnetConfig.has(`tokens.${configName}`)) {
    return null;
  }
  const tokenConfig = mainnetConfig.get(`tokens.${configName}`);

  if (!tokenConfig.has("address")) {
    console.warn(
      `Config for ${tokenName} does not specify an address on ${networkName}. Contract therefore not available.`
    );
    return null;
  }
  const tokenAddress = tokenConfig.get("address");
  if (!tokenConfig.has("abi")) {
    console.warn(
      `Config for ${tokenName} does not specify an abi file for on ${networkName}. Contract therefore not available.`
    );
    return null;
  }
  const tokenAbi = require(tokenConfig.get("abi"));

  console.info(`$ token ${tokenName} ABI loaded. Address: ${tokenAddress}`);
  return new ethers.Contract(tokenAddress, tokenAbi, ethers.provider);
}

function tryGetCompoundEnv(mainnetConfig, networkName, ethers) {
  if (!mainnetConfig.has("compound")) {
    return null;
  }
  let compoundConfig = mainnetConfig.get("compound");

  if (!compoundConfig.has("unitrollerAddress")) {
    console.warn(
      "Config for Compound does not specify a unitroller address. Compound is therefore not available."
    );
    return null;
  }
  const unitrollerAddress = compoundConfig.get("unitrollerAddress");
  if (!compoundConfig.has("unitrollerAbi")) {
    console.warn(
      `Config for Compound does not specify a unitroller abi file. Compound is therefore not available.`
    );
    return null;
  }
  const compAbi = require(compoundConfig.get("unitrollerAbi"));

  let compound = {
    contract: new ethers.Contract(unitrollerAddress, compAbi, ethers.provider),
  };

  if (compoundConfig.has("whale")) {
    const compoundWhale = compoundConfig.get("whale");
    compound.whale = compoundWhale;
  }

  console.info(
    `${networkName} Compound ABI loaded. Unitroller address: ${unitrollerAddress}`
  );
  return compound;
}

function tryGetAaveEnv(mainnetConfig, networkName, ethers) {
  if (!mainnetConfig.has("aave")) {
    return null;
  }
  const aaveConfig = mainnetConfig.get("aave");

  if (
    !(
      aaveConfig.has("addressesProviderAddress") &&
      aaveConfig.has("addressesProviderAbi") &&
      aaveConfig.has("lendingPoolAddress") &&
      aaveConfig.has("lendingPoolAbi")
    )
  ) {
    console.warn(
      "Config for Aave does not specify an address provider. Aave is therefore not available."
    );
    return null;
  }

  const addressesProviderAddress = aaveConfig.get("addressesProviderAddress");
  const lendingPoolAddress = aaveConfig.get("lendingPoolAddress");
  const addressesProviderAbi = require(aaveConfig.get("addressesProviderAbi"));
  const lendingPoolAbi = require(aaveConfig.get("lendingPoolAbi"));

  const addressesProvider = new ethers.Contract(
    addressesProviderAddress,
    addressesProviderAbi,
    ethers.provider
  );

  const lendingPool = new ethers.Contract(
    lendingPoolAddress,
    lendingPoolAbi,
    ethers.provider
  );

  const aave = {
    lendingPool: lendingPool,
    addressesProvider: addressesProvider,
  };

  console.info(
    `${networkName} Aave ABI loaded. LendingPool is at: ${lendingPoolAddress}`
  );
  return aave;
}

function tryGetMangroveEnv(mainnetConfig, networkName, ethers) {
  if (!mainnetConfig.has("mangrove")) {
    console.warn(`Mangrove is not pre deployed on ${networkName} mainnet`);
    return null;
  }
  mangroveConfig = mainnetConfig.get("mangrove");
  mangrove = {};

  if (!mangroveConfig.has("address")) {
    console.warn(
      "Config for Mangrove does not specify an address. Contract therefore not available."
    );
    return null;
  }
  const mangroveAddress = mangroveConfig.get("address");
  if (mangroveConfig.has("abi")) {
    console.info(
      "Config for Mangrove specifies an abi file, so using that instead of artifacts in .build"
    );
    const mangroveAbi = require(mangroveConfig.get("abi"));
    mangrove.contract = new ethers.Contract(
      mangroveAddress,
      mangroveAbi,
      ethers.provider
    );
  } else {
    // NB (Espen): Hardhat launches tasks without awaiting, so async loading of env makes stuff difficult.
    //             It's not clear to me how to support loading the ABI from .build without async
    // const mangroveContractFactory = await ethers.getContractFactory("Mangrove");
    // mangrove.contract = mangroveContractFactory.attach(mangroveAddress);
    console.warn(
      "Config for Mangrove does not specify an abi file. Mangrove env is therefore not available."
    );
  }

  console.info(
    `${networkName} Mangrove ABI loaded. Address: ${mangroveAddress}`
  );
  return mangrove;
}
