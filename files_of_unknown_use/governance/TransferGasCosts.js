const hre = require("hardhat");
const helper = require("../helper");
const chalk = require("chalk");

async function main() {
  // reading deploy oracle for the deployed network

  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );
  if (!process.env["MUMBAI_EMPTY_PURSE_PRIVATE_KEY"]) {
    console.error("No empty purse account defined");
  }
  const emptyWallet = new ethers.Wallet(
    process.env["MUMBAI_EMPTY_PURSE_PRIVATE_KEY"],
    helper.getProvider()
  );

  const weth = helper.contractOfToken("wEth");
  const dai = helper.contractOfToken("dai");
  const usdc = helper.contractOfToken("usdc");

  const oracle = helper.getAave().priceOracle;

  const tokens = [
    [weth, "WETH"],
    [dai, "DAI"],
    [usdc, "USDC"],
  ];

  for (const [token, tokenName] of tokens) {
    const tokenPrice = await oracle.getAssetPrice(token.address);
    console.log(
      `* 1 ${tokenName} is ${ethers.utils.formatUnits(
        tokenPrice,
        18
      )} ETH on AAVE`
    );
    const txEmpty = await token
      .connect(wallet)
      .transfer(emptyWallet.address, ethers.BigNumber.from(1));
    const receiptEmpty = await txEmpty.wait();
    console.log(
      `* ${tokenName} transfer to empty wallet is ${receiptEmpty.gasUsed}`
    );
    const tx = await token
      .connect(emptyWallet)
      .transfer(wallet.address, ethers.BigNumber.from(1));
    const receipt = await tx.wait();
    //    console.log(`* ${tokenName} transfer to non empty wallet is ${receipt.gasUsed}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
