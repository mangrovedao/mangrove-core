const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(network.config.url);

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
    // NSLOTS/2 offers giving base (~1000 USD each)
    // NSLOTS/2 offers giving quote (~1000 USD)

    let MangoRaw = (
      await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
    ).connect(deployer);
    if ((await MangoRaw.admin()) === deployer.address) {
      const tx = await MangoRaw.setAdmin(tester.address);
      await tx.wait();
    }
    MangoRaw = MangoRaw.connect(tester);

    const NSLOTS = await MangoRaw.NSLOTS();
    const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    const Mango = await MgvAPI.offerLogic(MangoRaw.address).liquidityProvider(
      market
    );
    const provBid = await Mango.computeBidProvision();
    const provAsk = await Mango.computeAskProvision();
    const totalFund = provAsk.add(provBid).mul(NSLOTS);

    // This does not work as listener of maker contract is not synched with listener of Mgv events
    // const filter_initialized = MangoRaw.filters.Initialized();
    // let listened = 0;
    // MangoRaw.on(filter_initialized, async (from, to, bidding) => {
    //   await market.requestBook(); //not helping
    //   if (bidding) {
    //     console.log(`=== Bids on market (${baseName},${quoteName}) ===`);
    //     market.consoleBids();
    //     listened++;
    //   } else {
    //     console.log(`=== Asks on market (${baseName},${quoteName}) ===`);
    //     market.consoleAsks();
    //     listened++;
    //   }
    //   if (listened == 2) {
    //     MangoRaw.removeAllListeners();
    //   }
    // });

    console.log(`* Funding mangrove (${totalFund} MATIC for Mango)`);
    const tx = await Mango.fundMangrove(totalFund);
    await tx.wait();

    console.log(
      `* Approving mangrove for ${baseName} and ${quoteName} transfer`
    );
    const tx1 = await Mango.approveMangroveForBase();
    const tx2 = await Mango.approveMangroveForQuote();
    await tx.wait();

    //TODO: should only provision if needed.
    console.log(
      `* Provisionning Mango with ${baseName} and ${quoteName} tokens`
    );
    await MgvAPI.token(baseName).transfer(
      MangoRaw.address,
      (NSLOTS / 2) * 0.325
    );
    await MgvAPI.token(quoteName).transfer(
      MangoRaw.address,
      (NSLOTS / 2) * 1000
    );

    console.log(`* Posting Mango offers on (${baseName},${quoteName}) market`);
    const slice = NSLOTS / 2;
    let bidding = true;
    let pivotIds = new Array(slice);
    let amounts = new Array(slice);
    // TODO: define a procedure to get better pivots
    pivotIds = pivotIds.fill(0, 0);
    amounts.fill(MgvAPI.toUnits(1000, quoteName), 0); // quotes are always in USD equivalent so using a volume of 1000 USD here

    for (let i = 0; i < 2; i++) {
      if (i >= 1) {
        bidding = false;
      }
      const receipt = await MangoRaw.initialize(
        bidding,
        false, //withQuotes
        slice * i, // from
        slice * (i + 1), // to
        [pivotIds, pivotIds],
        amounts
      );
      console.log(
        `* Slice [${[slice * i, slice * (i + 1)]}[ initialized (${
          (await receipt.wait()).gasUsed
        } gas used)`
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
