module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];

  const mangroveResult = await hre.deployments.deploy("Mangrove", {
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 500000 /*gasmax*/],
  });

  const mgvReader = await hre.deployments.deploy("MgvReader", {
    from: deployer,
    args: [mangroveResult.address],
  });

  const mgvCleaner = await hre.deployments.deploy("MgvCleaner", {
    from: deployer,
    args: [mangroveResult.address],
  });

  const oracle = await hre.deployments.deploy("MgvOracle", {
    from: deployer,
    args: [deployer, deployer],
  });
};

module.exports.tags = ["mumbai"];
