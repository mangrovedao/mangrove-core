module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];

  const runDeploy = async (name, args) => {
    const result = await hre.deployments.deploy(name, args);
    console.log(
      `${name}: ${
        result.newlyDeployed
          ? `newly deployed at ${result.address}`
          : "skipped (already deployed)"
      }`
    );
    return result;
  };

  const mangroveResult = await runDeploy("Mangrove", {
    contract: "Mangrove",
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 700000 /*gasmax*/],
    skipIfAlreadyDeployed: true,
  });

  await runDeploy("MgvReader", {
    contract: "MgvReader",
    from: deployer,
    args: [mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });

  await runDeploy("MgvCleaner", {
    from: deployer,
    args: [mangroveResult.address],
    skipIfAlreadyDeployed: true,
  });

  await runDeploy("MgvOracle", {
    from: deployer,
    args: [deployer, deployer],
    skipIfAlreadyDeployed: true,
  });

  await runDeploy("MangroveOrder", {
    from: deployer,
    args: [mangroveResult.address, deployer],
    skipIfAlreadyDeployed: true,
  });
};

module.exports.tags = ["mumbai"];
