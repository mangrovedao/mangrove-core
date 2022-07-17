const hre = require("hardhat");
const chalk = require("chalk");
const { getProvider } = require("../helper.js");
const { Mangrove } = require("../../../mangrove.js");

// NB: We currently use MangroveOrderEnriched instead of MangroveOrder, see https://github.com/mangrovedao/mangrove/issues/535
//     This script approves the contract pointed to by Mangrove.orderContract
async function main() {
  const provider = getProvider();
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

  const ercs = ["WETH", "DAI", "USDC"];
  const logic = MgvAPI.offerLogic(MgvAPI.orderContract.address);
  const tx = await logic.activate(ercs);
  await tx.wait();
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
