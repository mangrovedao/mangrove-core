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
    let MangoRaw = (
      await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
    ).connect(tester);
    if ((await MangoRaw.admin()) === deployer.address) {
      const tx = await MangoRaw.connect(deployer).setAdmin(tester.address);
      await tx.wait();
    }
    const N = await MangoRaw.NSLOTS();

    const tx1 = await MangoRaw.retractOffers(
      2, // both bids and asks
      0, // from
      Math.floor(N / 3) // to
    );
    await tx1.wait();
    const tx2 = await MangoRaw.retractOffers(
      2, // both bids and asks
      Math.floor(N / 3), // from
      Math.floor((2 * N) / 3) // to
    );
    await tx2.wait();
    const tx3 = await MangoRaw.retractOffers(
      2, // both bids and asks
      Math.floor((2 * N) / 3), // from
      N // to
    );
    await tx3.wait();
    //await Promise.all([tx1, tx2, tx3]);
    console.log(`Offers retracted on (${baseName},${quoteName}) market`);

    // const balBase = await MgvAPI.token(baseName).balanceOf(MangoRaw.address);
    // const balQuote = await MgvAPI.token(quoteName).balanceOf(MangoRaw.address);
    // const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    // const Mango = await MgvAPI.offerLogic(MangoRaw.address).liquidityProvider(
    //   market
    // );
    // // if treasury was set to Mango itself
    // await Mango.logic.redeemToken(baseName, tester.address, balBase);
    // await Mango.logic.redeemToken(quoteName, tester.address, balQuote);
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
