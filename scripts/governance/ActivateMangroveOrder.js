const hre = require("hardhat");
const chalk = require("chalk");
const { getProvider } = require("../helper.js");
const { Mangrove } = require("../../../mangrove.js");

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

  for (tokenName of ercs) {
    if (
      (await MgvAPI.token(tokenName).allowance({ owner: logic.address })).eq(0)
    ) {
      console.log(
        `* Approving Mangrove for transfering ${tokenName} from MangroveOrder (${chalk.grey(
          logic.address
        )})`
      );
      const tx = await logic.approveMangrove(tokenName);
      await tx.wait();
    } else {
      console.log(
        `* ${tokenName} already approved MangroveOrder (${chalk.grey(
          logic.address
        )}) for transferring ${tokenName}`
      );
    }
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
