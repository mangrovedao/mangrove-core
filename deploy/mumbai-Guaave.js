const { Mangrove } = require("../../mangrove.js");

module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];
  if (!deployer) {
    throw Error("No deployer account found in the hardhat environment.");
  }
  const signer = await hre.ethers.getSigner(deployer);
  const NSLOTS = 100;
  const MgvAPI = await Mangrove.connect({
    signer: signer,
  });
  const providerAddress = MgvAPI.getAddress("AaveProvider");
  const deployOnMarket = async (
    baseName,
    quoteName,
    base0,
    quote0,
    delta,
    providerAddress
  ) => {
    const Guaave = await hre.deployments.deploy(
      `Guaave_${baseName}_${quoteName}`,
      {
        contract: "Guaave",
        from: deployer,
        args: [
          MgvAPI.contract.address,
          MgvAPI.token(baseName).address, // base
          MgvAPI.token(quoteName).address,
          {
            base_0: MgvAPI.toUnits(base0, baseName),
            quote_0: MgvAPI.toUnits(quote0, quoteName),
            nslots: NSLOTS,
            delta: MgvAPI.toUnits(delta, quoteName),
          },
          {
            addressesProvider: providerAddress,
            referralCode: 0,
            interestRateMode: 1, // Stable
          },
          deployer, // default treasury for base and quote
        ],
        skipIfAlreadyDeployed: true,
      }
    );
    console.log(
      `Guaave deployed (${Guaave.address}) on market (${baseName},${quoteName}) of Mangrove (${MgvAPI.contract.address})`
    );
  };
  await deployOnMarket("WETH", "USDC", 1, 900, 32, providerAddress); // [900 USD/ETH,...,|2500|..., 4100 USD/ETH] inc 32 USD
  await deployOnMarket("WETH", "DAI", 1, 900, 32, providerAddress); // [900 DAI/ETH,..,|2500|,... 4100 USD/ETH] inc 32 DAI
  await deployOnMarket("DAI", "USDC", 1000, 997, 0.12, providerAddress); // Pmin=997/1000, inc=0.12/1000, Pmax= 997/1000 + 0.12*50/1000 = 1003/1000
};

module.exports.tags = ["mumbai-Guaave"];
