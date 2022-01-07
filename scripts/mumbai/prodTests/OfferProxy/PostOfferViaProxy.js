const hre = require("hardhat");
const helper = require("../../../helper");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const offerProxy = await hre.ethers.getContract("OfferProxy");
  console.log(await offerProxy.OFR_GASREQ());

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  const weth = MgvAPI.token("WETH");
  const dai = MgvAPI.token("DAI");
  const usdc = MgvAPI.token("USDC");

  MgvAPI._provider.pollingInterval = 250;
  const volume = 5000;

  const markets = [
    [weth, 4283, dai, 1],
    [weth, 4283, usdc, 1],
    [dai, 1, usdc, 1],
  ];

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const mkr = await MgvAPI.MakerConnect({
      address: offerProxy.address,
      base: base.name,
      quote: quote.name,
    });
    const fundTx = await mkr.fundMangrove(0.1);
    await fundTx.wait();
    // will hang if pivot ID not correctly evaluated
    const { id: ofrId } = await mkr.newAsk({
      wants: (volume + 12) / quoteInUSD,
      gives: volume / baseInUSD,
    });

    console.log(
      `* Posting new offer proxy ${ofrId} on (${base.name},${quote.name}) market`
    );
    const { id: ofrId_ } = await mkr.newBid({
      wants: (volume + 13) / baseInUSD,
      gives: volume / quoteInUSD,
    });

    console.log(
      `* Posting new offer proxy ${ofrId_} on (${base.name},${quote.name}) market`
    );
    MgvAPI.prettyPrint(mkr.market.book());
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
