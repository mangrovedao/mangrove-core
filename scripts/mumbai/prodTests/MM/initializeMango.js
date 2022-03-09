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
    let tx = null;
    let default_base_amount = baseName === "WETH" ? 0.3 : 1000;
    let default_quote_amount = quoteName === "WETH" ? 0.3 : 1000;
    // NSLOTS/2 offers giving base (~1000 USD each)
    // NSLOTS/2 offers giving quote (~1000 USD)

    let MangoRaw = (
      await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
    ).connect(deployer);

    if ((await MangoRaw.admin()) === deployer.address) {
      tx = await MangoRaw.setAdmin(tester.address);
      await tx.wait();
    }

    MangoRaw = MangoRaw.connect(tester);
    console.log(`* Set ${baseName} treasury to tester wallet`);
    tx = await MangoRaw.set_treasury(true, tester.address);
    await tx.wait();

    console.log(`* Set ${quoteName} treasury to tester wallet`);
    tx = await MangoRaw.set_treasury(false, tester.address);
    await tx.wait();

    const NSLOTS = await MangoRaw.NSLOTS();
    const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    const Mango = await MgvAPI.offerLogic(MangoRaw.address).liquidityProvider(
      market
    );
    const provBid = await Mango.computeBidProvision();
    const provAsk = await Mango.computeAskProvision();
    const totalFund = provAsk.add(provBid).mul(NSLOTS);

    console.log(`* Funding mangrove (${totalFund} MATIC for Mango)`);
    tx = await Mango.fundMangrove(totalFund);
    await tx.wait();

    console.log(
      `* Approving mangrove as spender for ${baseName} and ${quoteName} transfer from Mango`
    );
    let tx1 = await Mango.approveMangroveForBase();
    let tx2 = await Mango.approveMangroveForQuote();
    await tx1.wait();
    await tx2.wait();

    console.log(
      `* Approve Mango as spender for ${baseName} and ${quoteName} token transfer from tester wallet`
    );

    tx1 = await MgvAPI.token(baseName).approve(MangoRaw.address);
    tx2 = await MgvAPI.token(quoteName).approve(MangoRaw.address);
    await tx1.wait();
    await tx2.wait();

    console.log(`* Posting Mango offers on (${baseName},${quoteName}) market`);
    const batch = 5;
    const slice = NSLOTS / batch; // slices of 10 offers
    let pivotIds = new Array(slice);
    let amounts = new Array(slice);

    // TODO: define a procedure to get better pivots
    pivotIds = pivotIds.fill(0, 0);

    for (let i = 0; i < batch; i++) {
      const withBase = slice * i < 30;
      if (withBase) {
        amounts.fill(MgvAPI.toUnits(default_base_amount, baseName), 0, 10);
      } else {
        amounts.fill(MgvAPI.toUnits(default_quote_amount, quoteName), 0, 10);
      }
      const receipt = await MangoRaw.initialize(
        29, // last bid position
        withBase, // with base until Asking
        slice * i, // from
        slice * (i + 1), // to
        [pivotIds, pivotIds],
        amounts
      );
      await receipt.wait();
    }
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
