const fs = require("fs");
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
          deployer, // admin
        ],
        skipIfAlreadyDeployed: true,
      }
    );
    console.log(
      `Mango deployed (${Mango.address}) on market (${baseName},${quoteName}) of Mangrove (${MgvAPI.contract.address})`
    );
    return Mango;
  };
  let contracts = [];
  let i = 0;
  contracts[i++] = await deployOnMarket("WETH", "USDC", 1, 500, 36); // [500 USD/ETH,...,|2500|..., 4100 USD/ETH] inc 36 USD
  contracts[i++] = await deployOnMarket("WETH", "DAI", 1, 500, 36); // [500 DAI/ETH,..,|2500|,... 4100 USD/ETH] inc 36 DAI
  contracts[i++] = await deployOnMarket("DAI", "USDC", 1000, 997, 0.12); // Pmin=997/1000, inc=0.12/1000, Pmax= 997/1000 + 0.12*50/1000 = 1003/1000
  for (const contract of contracts) {
    await contract.deployed();
  }
};

module.exports.tags = ["mumbai-Mango"];
