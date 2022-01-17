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
    signer: wallet,
  });

  const repostLogic = MgvAPI.offerLogic(
    await hre.ethers.getContract("Reposting")
  );
  const admin = await repostLogic.admin();

  // if admin is still deployer, changing it to Mumbai tester
  if (admin != wallet.address) {
    console.log("* Setting new admin for Reposting offer");
    if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
      console.error("No tester account defined");
    }

    const walletDeployer = new ethers.Wallet(
      process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
      provider
    );

    // using walletDeployer signature to change admin
    // NB `connect` has no side effect on `repostLogic`
    const adminTx = await repostLogic
      .connect(walletDeployer)
      .setAdmin(wallet.address);
    await adminTx.wait();
  }

  const markets = [
    ["WETH", 4287, "USDC", 1],
    ["WETH", 4287, "DAI", 1],
    ["DAI", 1, "USDC", 1],
  ];

  const overrides = { gasLimit: 200000 };
  const volume = 1000;
  const gasreq = 200000;

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const txFund1 = await repostLogic.fundMangrove(
      await lp.computeAskProvision({ gasreq: gasreq })
    );
    const txFund2 = await repostLogic.fundMangrove(
      await lp.computeBidProvision({ gasreq: gasreq })
    );
    await txFund1.wait();
    await txFund2.wait();

    const txApp1 = await repostLogic.approveMangrove(base);
    const txApp2 = await repostLogic.approveMangrove(quote);
    await txApp1.wait();
    await txApp2.wait();

    await repostLogic.depositToken(base, volume / baseInUSD, overrides);
    console.log(
      `* Transferred ${volume / baseInUSD} ${base} to persistent offer logic`
    );
    await repostLogic.depositToken(quote, volume / quoteInUSD, overrides);
    console.log(
      `* Transferred ${volume / quoteInUSD} ${quote} to persistent offer logic`
    );

    // getting a liquidityProvider object to interact with Mangrove using Reposting offer.
    const lp = await repostLogic.liquidityProvider({
      base: base,
      quote: quote,
    });
    // will hang if pivot ID not correctly evaluated
    const { id: ofrId } = await lp.newAsk(
      {
        wants: (volume + 10) / quoteInUSD,
        gives: volume / baseInUSD,
        gasreq: gasreq,
      },
      overrides
    );
    const { id: ofrId_ } = await lp.newBid(
      {
        wants: (volume + 10) / baseInUSD,
        gives: volume / quoteInUSD,
        gasreq: gasreq,
      },
      overrides
    );
    const filter = [
      `id`,
      `gasreq`,
      `offer_gasbase`,
      `maker`,
      `price`,
      `volume`,
    ];
    await lp.market.consoleAsks(filter);
    await lp.market.consoleBids(filter);
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
