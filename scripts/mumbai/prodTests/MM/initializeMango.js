const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");
const { getProvider } = require("scripts/helper.js");

async function main() {
  const provider = getProvider();

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

  let router = null;

  for (const [baseName, quoteName] of markets) {
    let tx = null;
    // bids give quote, asks give base
    let default_ask_amount = baseName === "WETH" ? 0.25 : 1000;
    let default_bid_amount = quoteName === "WETH" ? 0.25 : 1000;
    default_ask_amount = MgvAPI.token(baseName).toUnits(default_ask_amount);
    default_bid_amount = MgvAPI.token(quoteName).toUnits(default_bid_amount);

    // NSLOTS/2 offers giving base (~1000 USD each)
    // NSLOTS/2 offers giving quote (~1000 USD)

    let MangoRaw = (
      await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
    ).connect(deployer);
    // in case deployment was interupted after the liquidity router was deployed
    if (!router) {
      router = await MangoRaw.router();
    }

    if ((await MangoRaw.admin()) === deployer.address) {
      tx = await MangoRaw.setAdmin(tester.address);
      await tx.wait();
    }

    MangoRaw = MangoRaw.connect(tester);

    let [pendingBase, pendingQuote] = await MangoRaw.pending();
    if (pendingBase.gt(0) || pendingQuote.gt(0)) {
      console.log(
        `* Current deployment of Mango has pending liquidity, resetting.`
      );
      tx = await MangoRaw.reset_pending();
      await tx.wait();
    }
    const RouterFactory = await ethers.getContractFactory("SimpleRouter");
    if (router === ethers.constants.AddressZero) {
      console.log(`* Deploying a new liquidity router`);
      const routerContract = await RouterFactory.connect(tester).deploy(
        tester.address
      );
      await routerContract.deployed();

      console.log(`* Binding router (${routerContract.address}) to this Mango`);
      tx = await routerContract.bind(MangoRaw.address);
      await tx.wait();
      router = routerContract.address;
    } else {
      console.log(`* Reusing already deployed router ${router}`);
      tx = await MangoRaw.set_router(router, await MangoRaw.ofr_gasreq());
      await tx.wait();
      const routerContract = RouterFactory.connect(tester).attach(router);
      tx = await routerContract.bind(MangoRaw.address);
      await tx.wait();
    }
    console.log(`* Telling Mango to route liquidity from tester's wallet`);
    tx = await MangoRaw.set_router(
      router,
      tester.address, // using tester's wallet
      await MangoRaw.ofr_gasreq()
    );
    await tx.wait();

    if ((await MgvAPI.token(baseName).allowance({ spender: router })).eq(0)) {
      // maker has to approve liquidity router of Mango for base and quote transfer
      console.log(
        `* Approving router to transfer ${baseName} from tester wallet`
      );
      tx = await MgvAPI.token(baseName).approve(
        router,
        ethers.constants.MaxUint256
      );
      await tx.wait();
    }
    if ((await MgvAPI.token(quoteName).allowance({ spender: router })).eq(0)) {
      console.log(
        `* Approving router to transfer ${quoteName} from tester wallet`
      );
      tx = await MgvAPI.token(quoteName).approve(
        router,
        ethers.constants.MaxUint256
      );
      await tx.wait();
    }

    const NSLOTS = (await MangoRaw.NSLOTS()).toNumber();
    const market = await MgvAPI.market({ base: baseName, quote: quoteName });
    const Mango = await MgvAPI.offerLogic(MangoRaw.address).liquidityProvider(
      market
    );
    const provBid = await Mango.computeBidProvision();
    console.log(
      `Actual provision needed for a Bid on (${baseName},${quoteName}) Market is ${provBid}`
    );
    const provAsk = await Mango.computeAskProvision();
    console.log(
      `Actual provision needed for an Ask on (${baseName},${quoteName}) Market is ${provAsk}`
    );
    const totalFund = provAsk.add(provBid).mul(NSLOTS);

    if (totalFund.gt(0)) {
      console.log(`* Funding mangrove (${totalFund} MATIC for Mango)`);
      tx = await Mango.fundMangrove(totalFund);
      await tx.wait();
    }

    if (await MangoRaw.is_paused()) {
      console.log("* Mango was previously paused. Restarting now...");
      tx = await MangoRaw.restart();
      await tx.wait();
    }

    if ((await MangoRaw.shift()).gt(0)) {
      console.warn(
        `* Posting Mango offers on (${baseName},${quoteName}) market (current price shift ${(
          await MangoRaw.shift()
        ).toNumber()})`
      );
    }

    const offers_per_slice = 10;
    const slices = NSLOTS / offers_per_slice; // slices of 10 offers

    let pivotIds = new Array(NSLOTS);
    let amounts = new Array(NSLOTS);

    pivotIds = pivotIds.fill(0, 0);
    // init amount is expressed in `makerGives` amount (i.e base for bids and quote for asks)
    amounts.fill(default_bid_amount, 0, NSLOTS / 2);
    amounts.fill(default_ask_amount, NSLOTS / 2, NSLOTS);

    for (let i = 0; i < slices; i++) {
      const receipt = await MangoRaw.initialize(
        true,
        NSLOTS / 2 - 1,
        offers_per_slice * i, // from
        offers_per_slice * (i + 1), // to
        [pivotIds, pivotIds],
        amounts
      );
      console.log(
        `Slice [${offers_per_slice * i},${
          offers_per_slice * (i + 1)
        }[ initialized (${(await receipt.wait()).gasUsed} gas used)`
      );
    }

    [pendingBase, pendingQuote] = await MangoRaw.pending();
    if (pendingBase.gt(0) || pendingQuote.gt(0)) {
      throw Error(
        `Init error, failed to initialize (${MgvAPI.token(baseName).fromUnits(
          pendingBase
        )} pending base,${MgvAPI.token(quoteName).fromUnits(
          pendingQuote
        )} pending quotes)`
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
