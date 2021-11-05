module.exports = async (hre) => {
  console.log(await hre.getUnnamedAccounts());
  const deployer = (await hre.getUnnamedAccounts())[0];

  // return;

  const mangroveResult = await hre.deployments.deploy("Mangrove", {
    from: deployer,
    args: [deployer /* governance */, 40 /*gasprice*/, 500000 /*gasmax*/],
  });

  const mgvReader = await hre.deployments.deploy("MgvReader", {
    from: deployer,
    args: [mangroveResult.address],
  });
};

module.exports.tags = ["mumbai"];
