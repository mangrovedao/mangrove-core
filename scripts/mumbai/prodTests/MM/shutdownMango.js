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
    let slice = 5;

    for (let i = 0; i < 2; i++) {
      const receipt = await MangoRaw.retractOffers(
        slice * i, // from
        slice * (i + 1) // to
      );
      console.log(`* Slice [${[slice * i, slice * (i + 1)]}[ retracted`);
    }

    const balBase = await MgvAPI.token(baseName).balanceOf(MangoRaw.address);
    const balQuote = await MgvAPI.token(quoteName).balanceOf(MangoRaw.address);
    const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    const Mango = await MgvAPI.offerLogic(MangoRaw.address).liquidityProvider(
      market
    );

    await Mango.logic.redeemToken(baseName, balBase);
    await Mango.logic.redeemToken(quoteName, balQuote);
    // const [bids, asks] = await MangoRaw.get_offers();
    // for (let i=0; i<10; i++) {
    //   if (bids[i]>0) {
    //     await Mango.cancelBid(bids[i].toNumber(), true);
    //   }
    //   if (asks[i]>0) {
    //     await Mango.cancelAsk(asks[i].toNumber(), true);
    //   }
    // }
    await Mango.logic.withdrawFromMangrove(await Mango.balanceOnMangrove());
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
