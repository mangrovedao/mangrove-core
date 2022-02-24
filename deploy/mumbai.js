module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];

  const mangroveResult = await hre.deployments.deploy("Mangrove", {
    contract: "Mangrove",
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 700000 /*gasmax*/],
    skipIfAlreadyDeployed: true,
  });

  const mgvReader = await hre.deployments.deploy("MgvReader", {
    contract: "MgvReader",
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
};

module.exports.tags = ["mumbai"];
