const hre = require("hardhat");
const chalk = require("chalk");
const { Mangrove } = require("../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(hre.network.config.url);
  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error(
      "No deployer account defined, make sure MUMBAI_DEPLOYER_PRIVATE_KEY is set"
    );
  }
  if (!process.env["MUMBAI_UPDATEGASBOT_ADDRESS"]) {
    console.error(
      "No updategas bot address defined, make sure MUMBAI_UPDATEGASBOT_ADDRESS is set"
    );
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });

  console.log(
    `Will set MgvOracle (${chalk.grey(
      MgvAPI.oracleContract.address
    )}) mutator to updategas bot address (${chalk.grey(
      process.env["MUMBAI_UPDATEGASBOT_ADDRESS"]
    )})`
  );
  await MgvAPI.oracleContract.setMutator(
    process.env["MUMBAI_UPDATEGASBOT_ADDRESS"]
  );

  console.log(
    `Will set Mangrove (${chalk.grey(
      MgvAPI.contract.address
    )}) monitor to MgvOracle (${chalk.grey(MgvAPI.oracleContract.address)})`
  );
  await MgvAPI.contract.setMonitor(MgvAPI.oracleContract.address);

  console.log(
    `Will set Mangrove (${chalk.grey(
      MgvAPI.contract.address
    )}) useOracle to true`
  );
  await MgvAPI.contract.setUseOracle(true);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
