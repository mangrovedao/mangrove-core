//const hre = require("hardhat");
const helper = require("../helper");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  for (const name of ["wEth", "dai", "usdc"]) {
    let decimals = 18;
    let amount = "10000";
    if (name == "usdc") {
      decimals = 6;
    }
    if (name == "wEth") {
      amount = "2";
    }
    const faucet = helper.getFaucet(name);
    const tx = await faucet
      .connect(wallet)
      .pull(ethers.utils.parseUnits(amount, decimals));
    console.log(`* Minting ${amount} ${name} for tester ${wallet.address}`);
    await tx.wait();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
