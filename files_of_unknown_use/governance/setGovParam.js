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

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });

  const overrides = { gasPrice: ethers.utils.parseUnits("60", "gwei") };
  switch (process.env["CONSTANT"]) {
    case "gasmax":
      const gasmax = parseInt(process.env["VALUE"]);
      const tx = await MgvAPI.contract.setGasmax(gasmax, overrides);
      await tx.wait();
      console.log(
        `Setting gasmax of Mangrove (${MgvAPI._address}) to ${gasmax}`
      );
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
