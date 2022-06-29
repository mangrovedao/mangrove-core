let deployer;

module.exports = async (hre) => {
  deployer = (await hre.getUnnamedAccounts())[0];
  if (!deployer) {
    throw Error("No deployer account is known to HH");
  }

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
    args: [deployer /* governance */, 40 /*gasprice*/, 1000000 /*gasmax*/],
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

  // We're currently using MangroveOrderEnriched instead of MangroveOrder, see https://github.com/mangrovedao/mangrove/issues/535
  // await runDeploy("MangroveOrder", {
  //   from: deployer,
  //   contract: "MangroveOrder",
  //   args: [mangroveResult.address, deployer],
  //   skipIfAlreadyDeployed: true,
  // });

  await runDeploy("MangroveOrderEnriched", {
    from: deployer,
    contract: "MangroveOrderEnriched",
    args: [mangroveResult.address, deployer],
    skipIfAlreadyDeployed: true,
  });
};

module.exports.tags = ["mumbai"];
