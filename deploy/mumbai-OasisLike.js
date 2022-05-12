const { Mangrove } = require("../../mangrove.js");

module.exports = async (hre) => {
  const deployer = (await hre.getUnnamedAccounts())[0];
  if (!deployer) {
    throw Error("No deployer account found in the hardhat environment.");
  }
  const signer = await hre.ethers.getSigner(deployer);
  const MgvAPI = await Mangrove.connect({
    signer: signer,
  });

  const Oasis = await hre.deployments.deploy("OasisLike", {
    from: deployer,
    args: [MgvAPI.contract.address, deployer],
    skipIfAlreadyDeployed: true,
  });
  console.log(
    `OasisLike multi maker contract deployed (${Oasis.address}), don't forget to activate it.`
  );
};

module.exports.tags = ["mumbai-OasisLike"];
