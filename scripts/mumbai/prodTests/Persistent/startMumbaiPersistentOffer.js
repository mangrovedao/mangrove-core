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

  MgvAPI._provider.pollingInterval = 250;

  const markets = [
    ["WETH", 4287, "USDC", 1],
    ["WETH", 4287, "DAI", 1],
    ["DAI", 1, "USDC", 1],
  ];

  const fundTx = await MgvAPI.fund(repostLogic.address, 0.5);
  await fundTx.wait();
  const overrides = { gasLimit: 200000 };
  const volume = 1000;

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const makerAPI = await MgvAPI.MakerConnect({
      address: repostLogic.address,
      base: base,
      quote: quote,
    });

    await makerAPI.approveMangrove(base);
    await makerAPI.approveMangrove(quote);
    await makerAPI.depositToken(base, volume / baseInUSD, overrides);
    console.log(
      `* Transferred ${volume / baseInUSD} ${base} to persistent offer logic`
    );
    await makerAPI.depositToken(quote, volume / quoteInUSD, overrides);
    console.log(
      `* Transferred ${volume / quoteInUSD} ${quote} to persistent offer logic`
    );
    // will hang if pivot ID not correctly evaluated
    const { id: ofrId } = await makerAPI.newAsk(
      {
        wants: (volume + 10) / quoteInUSD,
        gives: volume / baseInUSD,
      },
      overrides
    );
    const { id: ofrId_ } = await makerAPI.newBid(
      {
        wants: (volume + 10) / baseInUSD,
        gives: volume / quoteInUSD,
      },
      overrides
    );
    const market = await MgvAPI.market({ base: base, quote: quote });
    await market.consoleAsks();
    await market.consoleBids();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
