const hre = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(
    hre.network.config.url
  );

  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  const markets = [
    ["WETH", 4287, "USDC", 1],
    ["WETH", 4287, "DAI", 1],
    ["DAI", 1, "USDC", 1],
  ];

  const volume = 1000;

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const market = await MgvAPI.market({
      base: base,
      quote: quote,
      maxOffers: 100,
    });

    console.log(`* On market ${base},${quote}`);
    const tx_ = await market.approveMangrove(base.name);
    await tx_.wait();
    const tx = await market.approveMangrove(quote.name);
    await tx.wait();
    const resultBuy = await market.buy({
      wants: volume / baseInUSD,
      gives: (volume + 10) / quoteInUSD,
    });
    console.log(resultBuy);
    const resultSell = await market.sell({
      wants: volume / quoteInUSD,
      gives: (volume + 10) / baseInUSD,
    });
    console.log(resultSell);
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
