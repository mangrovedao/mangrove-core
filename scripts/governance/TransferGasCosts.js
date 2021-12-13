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
  const mgv = await helper.getMangrove();
  const weth = helper.contractOfToken("wEth").connect(wallet);
  const dai = helper.contractOfToken("dai").connect(wallet);
  const usdc = helper.contractOfToken("usdc").connect(wallet);
  const tokens = [
    [weth, "WETH"],
    [dai, "DAI"],
    [usdc, "USDC"],
  ];

  const overrides = { gasLimit: 100000 };
  for (const [token, tokenName] of tokens) {
    const tx = await token.transfer(
      wallet.address,
      ethers.BigNumber.from(1),
      overrides
    );
    const receipt = await tx.wait();
    console.log(`* ${tokenName} transfer is ${receipt.gasUsed}`);
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
