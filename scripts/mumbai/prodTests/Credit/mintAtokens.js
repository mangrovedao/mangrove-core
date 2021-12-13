//const hre = require("hardhat");
const helper = require("../helper");
const chalk = require("chalk");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );
  const lendingPool = helper.getAave().lendingPool.connect(wallet);

  for (const name of ["wEth", "dai", "usdc"]) {
    let decimals = 18;
    let amount = "4000";
    if (name == "usdc") {
      decimals = 6;
    }
    if (name == "wEth") {
      amount = "1";
    }
    const erc = helper.contractOfToken(name);
    const Approvetx = await erc
      .connect(wallet)
      .approve(lendingPool.address, ethers.constants.MaxUint256);
    await Approvetx.wait();

    let txGasReq = ethers.BigNumber.from(500000);
    let overrides = { gasLimit: txGasReq };
    const mintTx = await lendingPool.deposit(
      erc.address,
      ethers.utils.parseUnits(amount, decimals),
      wallet.address,
      0,
      overrides
    );
    const receipt = await mintTx.wait();

    console.log(
      `* Minting ${amount} ${name} on AAVE on behalf of ${wallet.address}...`,
      chalk.red(`(${ethers.utils.formatUnits(receipt.gasUsed, 3)}K gas used)`)
    );
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
