module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];

  const deployToken = async (tokenName, symbol, decimals = 18) => {
    await hre.deployments.deploy(tokenName, {
      contract: "MintableERC20BLWithDecimals",
      from: deployer,
      args: [deployer, tokenName, symbol, decimals],
      skipIfAlreadyDeployed: true,
    });
  };

  const tokenA = await deployToken("MGV_ETH", "MGV_ETH", 18);
  const tokenB = await deployToken("MGV_DAI", "MGV_DAI", 18);
  const tokenC = await deployToken("MGV_USD", "MGV_USD", 6);
};

module.exports.tags = ["mumbai-tokens"];
