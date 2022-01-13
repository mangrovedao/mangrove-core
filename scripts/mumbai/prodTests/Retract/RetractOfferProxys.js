const hre = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(
    hre.network.config.url
  );

  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No Deployer account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    provider
  );
  const offerProxy = (await hre.ethers.getContract("OfferProxy")).connect(
    wallet
  );

  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });

  const weth = MgvAPI.token("WETH");
  const dai = MgvAPI.token("DAI");
  const usdc = MgvAPI.token("USDC");

  const markets = [
    [weth, dai],
    [weth, usdc],
    [dai, usdc],
  ];

  for (const [base, quote] of markets) {
    const maker = await MgvAPI.makerConnect({
      address: offerProxy.address,
      base: base.name,
      quote: quote.name,
    });
    await maker.market.consoleAsks();
    for (const offer of maker.asks()) {
      if (offer.maker == offerProxy.address) {
        await maker.cancelAsk(offer.id, true);
        console.log(`* Ask ${offer.id} retracted`);
      }
    }
    await maker.market.consoleBids();
    for (const offer of maker.bids()) {
      if (offer.maker == offerProxy.address) {
        await maker.cancelBid(offer.id, true);
        console.log(`* Ask ${offer.id} retracted`);
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
