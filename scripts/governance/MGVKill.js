const hre = require("hardhat");
const chalk = require("chalk");
const util = require("util");
const readline = require("readline");
const rl = readline.createInterface(process.stdin, process.stdout);
const question = util.promisify(rl.question).bind(rl);
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
  console.log(`Will kill Mangrove (${chalk.grey(MgvAPI.contract.address)})`);
  console.log();

  const answer = await question(
    "Are you sure you want to kill Mangrove? Write 'kill' to confirm: "
  );
  if (answer === "kill") {
    await MgvAPI.contract.kill();
  } else {
    console.log("Ok, aborting");
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
