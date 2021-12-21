const hre = require("hardhat");
const helper = require("../../helper");
// const lc = require("../../lib/libcommon");
const { Mangrove } = require("../../../../mangrove.js");
// const chalk = require("chalk");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const MgvJS = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  MgvJS._provider.pollingInterval = 250;

  const market = await MgvJS.market({ base: "WETH", quote: "USDC" });
  await market.consoleAsks(["id", "maker", "volume", "price"]);
  await market.consoleBids(["id", "maker", "volume", "price"]);

  const tx = await MgvJS.token("USDC").approveMangrove();
  await tx.wait();

  const approval = await MgvJS.token("USDC").allowance();

  const repostLogic = await ethers.getContract("Reposting");
  const filter_Fail = repostLogic.filters.NotEnoughLiquidity();
  repostLogic.on(filter_Fail, (event) => {
    console.error("Offer logic failed");
  });

  // will hang if pivot ID not correctly evaluated
  const { got: takerGot, gave: takerGave } = await market.buy({
    volume: 1,
    price: 4291.287,
    slippage: 2,
  });
  console.log(
    `* Market Order complete  (${takerGot} USD for ${takerGave} WETH)`
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
