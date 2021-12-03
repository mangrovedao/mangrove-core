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
    args: [addressesProvider.address, mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });
};

module.exports.tags = ["mumbai"];
