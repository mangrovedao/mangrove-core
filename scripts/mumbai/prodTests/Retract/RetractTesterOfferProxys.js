const hre = require("hardhat");
const helper = require("../../../helper");
//const { logOrderBook } = require("../../lib/libcommon");
const chalk = require("chalk");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No Deployer account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );
  const offerProxy = (await hre.ethers.getContract("OfferProxy")).connect(
    wallet
  );

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
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
    const maker = await MgvAPI.MakerConnect({
      address: offerProxy.address,
      base: base.name,
      quote: quote.name,
    });
    const book = maker.market.book();

    MgvAPI.prettyPrint(book);
    for (const offer of book.asks) {
      if (offer.maker == offerProxy.address) {
        await maker.cancelAsk(offer.id, true);
        console.log(`* Ask ${offer.id} retracted`);
      }
    }
    for (const offer of book.bids) {
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
