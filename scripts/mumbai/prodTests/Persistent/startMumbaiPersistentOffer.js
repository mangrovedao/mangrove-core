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

  const overrides = { gasLimit: 200000 };
  const volume = 1000;
  const gasreq = 200000;
  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const makerAPI = await MgvAPI.makerConnect({
      address: repostLogic.address,
      base: base,
      quote: quote,
    });
    const txFund1 = await makerAPI.fundMangrove(
      await makerAPI.computeAskProvision({ gasreq: gasreq })
    );
    const txFund2 = await makerAPI.fundMangrove(
      await makerAPI.computeBidProvision({ gasreq: gasreq })
    );
    await txFund1.wait();
    await txFund2.wait();

    const txApp1 = await makerAPI.approveMangrove(base);
    const txApp2 = await makerAPI.approveMangrove(quote);
    await txApp1.wait();
    await txApp2.wait();

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
        gasreq: gasreq,
      },
      overrides
    );
    const { id: ofrId_ } = await makerAPI.newBid(
      {
        wants: (volume + 10) / baseInUSD,
        gives: volume / quoteInUSD,
        gasreq: gasreq,
      },
      overrides
    );
    const market = await MgvAPI.market({ base: base, quote: quote });
    const filter = [
      `id`,
      `gasreq`,
      `offer_gasbase`,
      `maker`,
      `price`,
      `volume`,
    ];
    market.consoleAsks(filter);
    market.consoleBids(filter);
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
