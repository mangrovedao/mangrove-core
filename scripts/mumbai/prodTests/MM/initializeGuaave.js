const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(network.config.url);

  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error("No deployer account defined");
  }
  const deployer = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const tester = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    signer: tester,
  });

  const markets = [
    ["WETH", "USDC"],
    ["WETH", "DAI"],
    ["DAI", "USDC"],
  ];
  for (const [baseName, quoteName] of markets) {
    let tx = null;
    let default_base_amount =
      baseName == "WETH"
        ? MgvAPI.toUnits(0.25, 18)
        : MgvAPI.toUnits(1000, baseName);
    let default_quote_amount =
      quoteName == "WETH"
        ? MgvAPI.toUnits(0.25, 18)
        : MgvAPI.toUnits(1000, quoteName);

    let GuaaveRaw = (
      await hre.ethers.getContract(`Guaave_${baseName}_${quoteName}`)
    ).connect(deployer);

    if ((await GuaaveRaw.admin()) === deployer.address) {
      tx = await GuaaveRaw.setAdmin(tester.address);
      await tx.wait();
    }

    GuaaveRaw = GuaaveRaw.connect(tester);
    if (!((await GuaaveRaw.get_treasury(true)) === tester.address)) {
      console.log(`* Set ${baseName} treasury to ${tester.address}`);
      tx = await GuaaveRaw.set_treasury(true, tester.address);
      await tx.wait();
    }
    if (!((await GuaaveRaw.get_treasury(false)) === tester.address)) {
      console.log(`* Set ${quoteName} treasury to ${tester.address}`);
      tx = await GuaaveRaw.set_treasury(false, GuaaveRaw.address);
      await tx.wait();
    }

    const NSLOTS = (await GuaaveRaw.NSLOTS()).toNumber();
    const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    const Guaave = await MgvAPI.offerLogic(GuaaveRaw.address).liquidityProvider(
      market
    );
    const provBid = await Guaave.computeBidProvision();
    console.log(
      `Actual provision needed for a Bid on (${baseName},${quoteName}) Market is ${provBid}`
    );
    const provAsk = await Guaave.computeAskProvision();
    console.log(
      `Actual provision needed for an Ask on (${baseName},${quoteName}) Market is ${provAsk}`
    );
    const totalFund = provAsk.add(provBid).mul(NSLOTS);

    if (totalFund.gt(0)) {
      console.log(`* Funding mangrove (${totalFund} MATIC for Guaave)`);
      tx = await Guaave.fundMangrove(totalFund);
      await tx.wait();
    }

    // checking if deployment of Guaave is paused
    if (await GuaaveRaw.is_paused()) {
      console.log(`* Restarting a previously paused Guaave instance`);
      tx = await GuaaveRaw.restart();
      await tx.wait();
    }

    let [pendingBase, pendingQuote] = await GuaaveRaw.get_pending();
    if (pendingBase.gt(0) || pendingQuote.gt(0)) {
      console.log(
        `* Current deployment of Guaave has pending liquidity, resetting.`
      );
      tx = await GuaaveRaw.reset_pending();
    }

    console.log(
      `* Posting Guaave offers on (${baseName},${quoteName}) market (current price shift ${(
        await GuaaveRaw.get_shift()
      ).toNumber()})`
    );
    const offers_per_slice = 10;
    const slices = NSLOTS / offers_per_slice; // slices of 10 offers

    let pivotIds = new Array(NSLOTS);
    let amounts = new Array(NSLOTS);

    pivotIds = pivotIds.fill(0, 0);
    // init amount is expressed in `makerGives` amount (i.e base for bids and quote for asks)
    amounts.fill(default_base_amount, 0, NSLOTS / 2);
    amounts.fill(default_quote_amount, NSLOTS / 2, NSLOTS);

    for (let i = 0; i < slices; i++) {
      const receipt = await GuaaveRaw.initialize(
        NSLOTS / 2 - 1,
        offers_per_slice * i, // from
        offers_per_slice * (i + 1), // to
        [pivotIds, pivotIds],
        amounts
      );
      console.log(
        `Slice initialized (${(await receipt.wait()).gasUsed} gas used)`
      );
    }
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
