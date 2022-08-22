const hre = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(hre.network.config.url);
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

  const logic = MgvAPI.offerLogic(
    (await hre.ethers.getContract("OfferProxy")).address
  );

  const aweth = MgvAPI.token("amWETH");
  const adai = MgvAPI.token("amDAI");
  const ausdc = MgvAPI.token("amUSDC");

  const volume = 1000;

  for (aToken of [aweth, adai, ausdc]) {
    const tx = await aToken.approve(logic.address);
    await tx.wait();
    console.log(`* Approving OfferProxy for ${aToken.name} transfer`);
  }

  const markets = [
    ["WETH", 2800, "DAI", 1],
    ["WETH", 2800, "USDC", 1],
    ["DAI", 1, "USDC", 1],
  ];

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    //getting a liquidity provider API on the (base,quote) market
    const lp = await logic.liquidityProvider({
      base: base,
      quote: quote,
    });
    // computing necessary provision to post a bid and a ask using offerProxy logic
    const provAsk = await lp.computeAskProvision();
    const provBid = await lp.computeBidProvision();

    const fundTx = await lp.fundMangrove(provAsk.add(provBid));
    await fundTx.wait();

    // will hang if pivot ID not correctly evaluated
    const { id: ofrId, pivot: pivot } = await lp.newAsk(
      {
        wants: (volume + 12) / quoteInUSD,
        gives: volume / baseInUSD,
      },
      { gasLimit: 200000 }
    );

    console.log(
      `* Posting new offer proxy ${ofrId} on (${base},${quote}) market using pivot ${pivot}`
    );
    const { id: ofrId_, pivot: pivot_ } = await lp.newBid(
      {
        wants: (volume + 13) / baseInUSD,
        gives: volume / quoteInUSD,
      },
      { gasLimit: 200000 }
    );

    console.log(
      `* Posting new offer proxy ${ofrId_} on (${base},${quote}) market using pivot ${pivot_}`
    );
    lp.market.consoleAsks();
    lp.market.consoleBids();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
