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

  const offerProxy = await hre.ethers.getContract("OfferProxy");

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  const weth = MgvAPI.token("WETH");
  const dai = MgvAPI.token("DAI");
  const usdc = MgvAPI.token("USDC");
  const aweth = MgvAPI.token("amWETH");
  const adai = MgvAPI.token("amDAI");
  const ausdc = MgvAPI.token("amUSDC");

  const volume = 1000;

  for (aToken of [aweth, adai, ausdc]) {
    const tx = await aToken.approve(offerProxy.address);
    await tx.wait();
    console.log(`* Approving OfferProxy for ${aToken.name} transfer`);
  }

  const markets = [
    [weth, 4300, dai, 1],
    [weth, 4300, usdc, 1],
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
    const { id: ofrId, pivot: pivot } = await mkr.newAsk({
      wants: (volume + 12) / quoteInUSD,
      gives: volume / baseInUSD,
    });

    console.log(
      `* Posting new offer proxy ${ofrId} on (${base.name},${quote.name}) market using pivot ${pivot}`
    );
    const { id: ofrId_, pivot: pivot_ } = await mkr.newBid({
      wants: (volume + 13) / baseInUSD,
      gives: volume / quoteInUSD,
    });

    console.log(
      `* Posting new offer proxy ${ofrId_} on (${base.name},${quote.name}) market using pivot ${pivot_}`
    );
    await mkr.market.consoleAsks();
    await mkr.market.consoleBids();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
