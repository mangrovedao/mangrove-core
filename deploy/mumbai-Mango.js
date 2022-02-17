const fs = require("fs");
const { Mangrove } = require("../../mangrove.js");

module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];
  if (!deployer) {
    throw Error("No deployer account found in the hardhat environment.");
  }
  const signer = await hre.ethers.getSigner(deployer);
  const NSLOTS = 30;
  const MgvAPI = await Mangrove.connect({
    signer: signer,
  });

  const deployOnMarket = async (baseName, quoteName, base0, quote0, delta) => {
    const Mango = await hre.deployments.deploy("Mango", {
      from: deployer,
      args: [
        MgvAPI.contract.address,
        MgvAPI.token(baseName).address, // base
        MgvAPI.token(quoteName).address, // quote
        // Pmin = QUOTE0/BASE0
        MgvAPI.toUnits(base0, baseName),
        MgvAPI.toUnits(quote0, quoteName), // QUOTE0
        NSLOTS, // price slots
        MgvAPI.toUnits(delta, quoteName), // quote progression
      ],
      //skipIfAlreadyDeployed: true,
    });
    console.log(
      `Mango deployed (${Mango.address}) on market (${baseName},${quoteName})`
    );
    fs.renameSync(
      `./deployments/${hre.network.name}/Mango.json`,
      `./deployments/${hre.network.name}/Mango_${baseName}_${quoteName}.json`
    );
  };
  await deployOnMarket("WETH", "USDC", 0.3, 1000, 30);
  await deployOnMarket("WETH", "DAI", 0.3, 1000, 30); //
  await deployOnMarket("DAI", "USDC", 1000, 997, 0.1); // min price 0.997
};

module.exports.tags = ["mumbai-Mango"];
