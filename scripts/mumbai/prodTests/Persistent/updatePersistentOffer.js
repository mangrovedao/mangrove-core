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

  const repostLogic = await hre.ethers.getContract("Reposting");
  const admin = await repostLogic.admin();

  // if admin is still deployer, changing it to Mumbai tester
  if (admin != wallet.address) {
    if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
      console.error("No tester account defined");
    }

    const walletDeployer = new ethers.Wallet(
      process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
      provider
    );

    const adminTx = await repostLogic
      .connect(walletDeployer)
      .setAdmin(wallet.address);
    await adminTx.wait();
  }

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  const markets = [
    ["WETH", 3500, "USDC", 1],
    ["WETH", 3500, "DAI", 1],
    ["DAI", 1, "USDC", 1],
  ];

  const fundTx = await MgvAPI.fund(repostLogic.address, 0.5);
  await fundTx.wait();
  const volume = 1000;
  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const Maker = await MgvAPI.MakerConnect({
      base: base,
      quote: quote,
      maxOffers: 100,
    });

    await Maker.market.consoleAsks();
    await Maker.market.consoleBids();
    for (const offer of Maker.asks()) {
      Maker.updateAsk;
    }

    const resultBuy = await market.buy({
      wants: volume / baseInUSD,
      gives: (volume + 11) / quoteInUSD,
    });
    console.log(resultBuy);
    const resultSell = await market.sell({
      wants: volume / quoteInUSD,
      gives: (volume + 11) / baseInUSD,
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
