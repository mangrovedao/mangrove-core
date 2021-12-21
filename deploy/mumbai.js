module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];

  const mangroveResult = await hre.deployments.deploy("Mangrove", {
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 500000 /*gasmax*/],
    skipIfAlreadyDeployed: true,
  });

  const mgvReader = await hre.deployments.deploy("MgvReader", {
    from: deployer,
    args: [mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });

  const mgvCleaner = await hre.deployments.deploy("MgvCleaner", {
    from: deployer,
    args: [mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });

  const oracle = await hre.deployments.deploy("MgvOracle", {
    from: deployer,
    args: [deployer, deployer],
    skipIfAlreadyDeployed: true,
  });

  const minter = await hre.deployments.deploy("Reposting", {
    from: deployer,
    args: [mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });

  const addressesProvider =
    require("../scripts/helper").getAave().addressesProvider;
  const offerProxy = await hre.deployments.deploy("OfferProxy", {
    from: deployer,
    args: [
      addressesProvider.address,
      mgvReader.address,
      mangroveResult.address,
    ],
    skipIfAlreadyDeployed: true,
  });

  const mangroveResult2 = await hre.deployments.deploy("Mangrove-2", {
    contract: "Mangrove",
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 700000 /*gasmax*/],
    skipIfAlreadyDeployed: true,
  });

  const mgvReader2 = await hre.deployments.deploy("MgvReader-2", {
    contract: "MgvReader",
    from: deployer,
    args: [mangroveResult2.address],
    skipIfAlreadyDeployed: true,
  });
};

module.exports.tags = ["mumbai"];
