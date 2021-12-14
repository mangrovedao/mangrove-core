// const hre = require("hardhat");
const helper = require("../../helper");
// const lc = require("../../lib/libcommon");
const { Mangrove, MgvToken } = require("../../../../mangrove.js");
// const chalk = require("chalk");

function prettyPrintBook(book) {
  console.table(book.asks, ["maker", "gives", "volume", "price"]);
  console.table(book.bids, ["maker", "wants", "volume", "price"]);
}

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
  prettyPrintBook(await market.book());

  const tx = await MgvJS.token("USDC").approveMgv();
  await tx.wait();

  const approval = await MgvJS.token("USDC").allowance();

  // will hang if pivot ID not correctly evaluated
  const { got: takerGot, gave: takerGave } = await market.buy({
    volume: 1.4,
    price: 5000,
  });
  console.log(
    `* Market Order complete  (${takerGot} ETH for ${takerGave} USD)`
  );
  prettyPrintBook(await market.book());
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
