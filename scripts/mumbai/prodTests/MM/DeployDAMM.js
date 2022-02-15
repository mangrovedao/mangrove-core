const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(network.config.url);

  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );
  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });
  const DAMM = (await ethers.getContractFactory("DAMM")).connect(wallet);
  const NSLOTS = 10;
  const delta = MgvAPI.toUnits(100, "USDC");

  const MMraw = await DAMM.deploy(
    MgvAPI.contract.address,
    MgvAPI.token("WETH").address, // base
    MgvAPI.token("USDC").address, // quote
    // Pmin = QUOTE0/BASE0
    MgvAPI.toUnits(0.34, "WETH"),
    MgvAPI.toUnits(1000, "USDC"), // QUOTE0
    NSLOTS, // price slots
    delta //quote progression
  );
  const market = await MgvAPI.market({ base: "WETH", quote: "USDC" });
  const MMLogic = await MgvAPI.offerLogic(MMraw.address).liquidityProvider(
    market
  );
  const provBid = await MMLogic.computeBidProvision();
  const provAsk = await MMLogic.computeAskProvision();
  const totalFund = provAsk.add(provBid).mul(NSLOTS);
  console.log(`* Funding mangrove (${totalFund} MATIC)`);
  await MMLogic.fundMangrove(totalFund);

  let slice = NSLOTS / 2;
  let bidding = true;
  let pivotIds = new Array(slice);
  let amounts = new Array(slice);
  pivotIds = pivotIds.fill(0, 0);
  amounts.fill(MgvAPI.toUnits(1000, "USDC"), 0);

  for (let i = 0; i < 2; i++) {
    if (i >= 1) {
      bidding = false;
    }
    const receipt = await MMraw.initialize(
      bidding,
      false, //withQuotes
      slice * i, // from
      slice * (i + 1), // to
      [pivotIds, pivotIds],
      amounts
    );
    console.log(
      `Slice initialized (${(await receipt.wait()).gasUsed} gas used)`
    );
  }
  market.consoleAsks();
  market.consoleBids();
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
