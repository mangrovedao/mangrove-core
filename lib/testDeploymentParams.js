const hre = require("hardhat");

module.exports = async () => {
  const deployer = (await hre.getNamedAccounts()).deployer;

  const withAddress = async (params) => {
    const { address } = await hre.deployments.deterministic(
      params.name,
      params.options
    );
    params.address = address;
    return params;
  };

  const mangrove = await withAddress({
    name: "Mangrove",
    options: {
      from: deployer,
      args: [deployer /* governance */, 1 /*gasprice*/, 500000 /*gasmax*/],
    },
  });

  const makeToken = (tokenName, symbol, decimals = 18) => {
    return {
      name: symbol,
      token: true,
      options: {
        contract: "TestTokenWithDecimals",
        from: deployer,
        args: [deployer, tokenName, symbol, decimals],
      },
    };
  };

  const tokenA = await withAddress(makeToken("Token A", "TokenA"));
  const tokenB = await withAddress(makeToken("Token B", "TokenB"));
  const Dai = await withAddress(makeToken("Dai Stablecoin", "DAI", 18));
  const Usdc = await withAddress(makeToken("USDC", "USDC", 6));
  const Weth = await withAddress(makeToken("WETH", "WETH", 18));

  const mgvReader = await withAddress({
    name: "MgvReader",
    token: false,
    options: {
      from: deployer,
      args: [mangrove.address],
    },
  });

  const mgvCleaner = await withAddress({
    name: "MgvCleaner",
    token: false,
    options: {
      from: deployer,
      args: [mangrove.address],
    },
  });

  const gasUpdater = (await hre.getNamedAccounts()).gasUpdater;

  const mgvOracle = await withAddress({
    name: "MgvOracle",
    options: {
      from: deployer,
      args: [deployer, gasUpdater],
    },
  });

  const maker = (await hre.getNamedAccounts()).maker;

  const testMaker = await withAddress({
    name: "TestMaker",
    token: false,
    options: {
      from: maker,
      args: [mangrove.address, tokenA.address, tokenB.address],
    },
  });

  return [
    mangrove,
    mgvReader,
    mgvCleaner,
    tokenA,
    tokenB,
    Dai,
    Usdc,
    Weth,
    testMaker,
    mgvOracle,
  ];
};
