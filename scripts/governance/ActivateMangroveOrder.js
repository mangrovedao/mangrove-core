const hre = require("hardhat");
const chalk = require("chalk");
const { Mangrove } = require("../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(hre.network.config.url);
  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });
  console.log(
    `Will activate MangroveOrder (${chalk.grey(MgvAPI.orderContract.address)})`
  );
  const ercs = ["WETH", "DAI", "USDC"];
  const logic = MgvAPI.offerLogic(MgvAPI.orderContract.address);
  for (tokenName of ercs) {
    console.log(
      `* approving Mangrove for transfering ${tokenName} from MangroveOrder`
    );
    const tx = await logic.approveMangrove(tokenName);
    await tx.wait();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
