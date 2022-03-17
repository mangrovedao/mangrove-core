const fs = require("fs");
const { Mangrove } = require("../../mangrove.js");

module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];
  if (!deployer) {
    throw Error("No deployer account found in the hardhat environment.");
  }
  const signer = await hre.ethers.getSigner(deployer);
  const NSLOTS = 50;
  const MgvAPI = await Mangrove.connect({
    signer: signer,
  });

  const deployOnMarket = async (baseName, quoteName, base0, quote0, delta) => {
    const Mango = await hre.deployments.deploy(
      `Mango_${baseName}_${quoteName}`,
      {
        contract: "Mango",
        from: deployer,
        args: [
          MgvAPI.contract.address,
          MgvAPI.token(baseName).address, // base
          MgvAPI.token(quoteName).address, // quote
          // Pmin = QUOTE0/BASE0
          MgvAPI.toUnits(base0, baseName), // BASE0
          MgvAPI.toUnits(quote0, quoteName), // QUOTE0
          NSLOTS, // price slots
          MgvAPI.toUnits(delta, quoteName), // quote progression
        ],
        skipIfAlreadyDeployed: true,
      }
    );
    console.log(
      `Mango deployed (${Mango.address}) on market (${baseName},${quoteName})`
    );
  };
  await deployOnMarket("WETH", "USDC", 1, 2000, 32); // [2000 USD/ETH,...,|2800|..., 3600 USD/ETH] inc 32 USD
  await deployOnMarket("WETH", "DAI", 1, 2000, 32); // [2000 DAI/ETH,..,|2800|,... 3600 USD/ETH] inc 32 DAI
  await deployOnMarket("DAI", "USDC", 1000, 997, 0.12); // Pmin=997/1000, inc=0.12/1000, Pmax= 997/1000 + 0.12*50/1000 = 1003/1000
};

module.exports.tags = ["mumbai-Mango"];
