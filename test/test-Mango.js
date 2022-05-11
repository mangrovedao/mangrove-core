const { assert } = require("chai");
const { existsSync } = require("fs");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const lc = require("../lib/libcommon.js");

async function checkOB(msg, mgv, outb, inb, bigNumbers, t) {
  for (const i in t) {
    let id;
    if (t[i] <= 0) {
      const [offer] = await mgv.offerInfo(outb, inb, -t[i]);
      assert(offer.gives.eq(0), `Offer ${-t[i]} should not be on the book`);
      id = -t[i];
    } else {
      const [offer] = await mgv.offerInfo(outb, inb, t[i]);
      assert(!offer.gives.eq(0), `Offer ${t[i]} is not live`);
      id = t[i];
    }
    assert(
      bigNumbers[i].eq(id),
      `Offer ${id} misplaced, seeing ${bigNumbers[i].toNumber()}`
    );
  }
}

async function init(NSLOTS, makerContract, bidAmount, askAmount) {
  let slice = NSLOTS / 2;
  let pivotIds = new Array(NSLOTS);
  let amounts = new Array(NSLOTS);
  pivotIds = pivotIds.fill(0, 0);
  amounts.fill(bidAmount, 0, NSLOTS / 2);
  amounts.fill(askAmount, NSLOTS / 2, NSLOTS);

  for (let i = 0; i < 2; i++) {
    const receipt = await makerContract.initialize(
      4,
      slice * i, // from
      slice * (i + 1), // to
      [pivotIds, pivotIds],
      amounts
    );
    console.log(
      `Slice initialized (${(await receipt.wait()).gasUsed} gas used)`
    );
  }
}

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let usdc = null;
  let wEth = null;
  let maker = null;
  let taker = null;
  let makerContract = null;
  const NSLOTS = 10;
  // price increase is delta/BASE_0
  const delta = lc.parseToken("34", 6); //  (in quotes!)

  before(async function () {
    // fetches all token contracts
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");

    // setting testRunner signer
    [maker, taker] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    [mgv, reader] = await lc.deployMangrove();
    await lc.activateMarket(mgv, wEth.address, usdc.address);
    await lc.fund([
      ["WETH", "50.0", taker.address],
      ["USDC", "100000", taker.address],
    ]);
  });

  it("Deploy strat", async function () {
    //lc.listenMgv(mgv);
    const strategy = "Mango";
    const Strat = await ethers.getContractFactory(strategy);

    // deploying strat
    makerContract = (
      await Strat.deploy(
        mgv.address,
        wEth.address, // base
        usdc.address, // quote
        // Pmin = QUOTE0/BASE0
        ethers.utils.parseEther("0.34"), // BASE0
        ethers.utils.parseUnits("1000", 6), // QUOTE0
        NSLOTS, // price slots
        delta //quote progression
      )
    ).connect(maker);

    // funds come from deployer's wallet by default
    await lc.fund([
      ["WETH", "17.0", maker.address],
      ["USDC", "50000", maker.address],
    ]);
    //await makerContract.setGasreq(ethers.BigNumber.from(500000));
    const prov = await makerContract.getMissingProvision(
      wEth.address,
      usdc.address,
      await makerContract.OFR_GASREQ(),
      0,
      0
    );

    const fundTx = await mgv["fund(address)"](makerContract.address, {
      value: prov.mul(20),
    });
    await fundTx.wait();

    await init(
      NSLOTS,
      makerContract,
      ethers.utils.parseUnits("1000", 6),
      ethers.utils.parseEther("0.3")
    );
    let [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [1, 2, 3, 4, 5, 0, 0, 0, 0, 0]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 0, 0, 0, 0, 1, 2, 3, 4, 5]
    );
  });
  it("Market orders", async function () {
    // let book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    // console.log("===bids===");
    // await lc.logOrderBook(book, usdc, wEth);
    // book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    // console.log("===asks===");
    // await lc.logOrderBook(book, wEth, usdc);

    await makerContract.approveMangrove(wEth.address);
    await makerContract.approveMangrove(usdc.address);

    await wEth.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    await wEth
      .connect(maker)
      .approve(makerContract.address, ethers.constants.MaxUint256);
    await usdc
      .connect(maker)
      .approve(makerContract.address, ethers.constants.MaxUint256);

    let [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "WETH", // outbound
      "USDC", // inbound
      ethers.utils.parseEther("0.5"), // wants
      ethers.utils.parseUnits("3000", 6) // gives
    );

    let [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [1, 2, 3, 4, 5, 6, 0, 0, 0, 0]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 0, 0, 0, 0, -1, 2, 3, 4, 5]
    );

    lc.assertEqualBN(
      takerGot,
      lc.netOf(ethers.utils.parseEther("0.5"), 30),
      "Incorrect received amount"
    );
    lc.assertEqualBN(
      bounty,
      ethers.utils.parseEther("0"),
      "Taker should not receive a bounty"
    );

    // book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    // console.log("===bids===");
    // await lc.logOrderBook(book, usdc, wEth);
    // book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    // console.log("===asks===");
    // await lc.logOrderBook(book, wEth, usdc);

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("3500", 6), // wants
      ethers.utils.parseEther("1.5") // gives
    );
    [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [1, 2, 3, 4, -5, -6, 0, 0, 0, 0]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 0, 0, 0, 6, 1, 2, 3, 4, 5]
    );

    lc.assertEqualBN(
      takerGot,
      lc.netOf(ethers.utils.parseUnits("3500", 6), 30),
      "Incorrect received amount"
    );
    lc.assertEqualBN(
      bounty,
      ethers.utils.parseEther("0"),
      "Taker should not receive a bounty"
    );
  });

  it("Negative shift", async function () {
    //console.log(chalk.yellow("Shifting"), chalk.red(-2));
    await makerContract.set_shift(-2, false, [
      ethers.utils.parseUnits("1000", 6),
      ethers.utils.parseUnits("1000", 6),
    ]);
    let [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [8, 7, 1, 2, 3, 4, -5, -6, 0, 0]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [-4, -5, 0, 0, 0, 0, 6, 1, 2, 3]
    );

    // book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    // console.log("===bids===");
    // await lc.logOrderBook(book, usdc, wEth);
    // book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    // console.log("===asks===");
    // await lc.logOrderBook(book, wEth, usdc);

    //console.log(chalk.yellow("Shifting"), chalk.green(3));
  });

  it("Positive shift", async function () {
    await makerContract.set_shift(3, true, [
      ethers.utils.parseUnits("0.3", 18),
      ethers.utils.parseUnits("0.3", 18),
      ethers.utils.parseUnits("0.3", 18),
    ]);

    [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [2, 3, 4, -5, -6, 0, 0, -8, -7, -1]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 0, 0, 6, 1, 2, 3, 4, 5, 7]
    );
  });

  it("Test partial fill", async function () {
    // scenario:
    // - set density so high that offer can no longer be updated
    // - run a market order and check that bid is not updated after ask is being consumed
    // - verify takerGave is pending
    // - put back the density and run another market order

    let tx = await mgv.setDensity(
      wEth.address,
      usdc.address,
      ethers.utils.parseUnits("1", 18)
    );
    await tx.wait();

    let density = (await mgv.configInfo(wEth.address, usdc.address)).local
      .density;
    lc.assertEqualBN(
      ethers.utils.parseUnits("1", 18),
      density,
      "Density was not correctly set"
    );

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("0.01", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );

    let best = await mgv.best(wEth.address, usdc.address);
    let offerInfo = await mgv.offerInfo(wEth.address, usdc.address, best);
    let old_gives = offerInfo.offer.gives;

    let [pendingBase] = await makerContract.get_pending();

    lc.assertEqualBN(
      pendingBase,
      takerGave,
      "Taker liquidity should be pending"
    );

    // tx = await mgv.setDensity(wEth.address, usdc.address, 100);
    // await tx.wait();

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("0.01", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );

    let [pendingBase_] = await makerContract.get_pending();
    lc.assertEqualBN(
      pendingBase_,
      pendingBase.add(takerGave),
      "Missing pending base"
    );

    tx = await mgv.setDensity(wEth.address, usdc.address, 100);
    await tx.wait();

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("0.01", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );
    let [pendingBase__] = await makerContract.get_pending();
    lc.assertEqualBN(pendingBase__, 0, "There should be no more pending base");

    best = await mgv.best(wEth.address, usdc.address);
    offerInfo = await mgv.offerInfo(wEth.address, usdc.address, best);

    lc.assertEqualBN(
      offerInfo.offer.gives,
      old_gives.add(pendingBase_.add(takerGave)),
      "Incorrect given amount"
    );
  });

  it("Test residual", async function () {
    let tx = await mgv.setDensity(
      usdc.address,
      wEth.address,
      ethers.utils.parseUnits("1", 6)
    );
    await tx.wait();
    tx = await mgv.setDensity(
      wEth.address,
      usdc.address,
      ethers.utils.parseUnits("1", 18)
    );
    await tx.wait();

    // market order will take the following best offer
    let best = await mgv.best(usdc.address, wEth.address);
    let offerInfo = await mgv.offerInfo(usdc.address, wEth.address, best);

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("100", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );
    // because density reqs are so high on both semi order book, best will not be able to self repost
    // and residual will be added to USDC (quote) pending pool
    // and what taker gave will not be added in the dual offer and added to the WETH (base) pending pool

    let [pendingBase, pendingQuote] = await makerContract.get_pending();

    lc.assertEqualBN(
      takerGave,
      pendingBase,
      "TakerGave was not added to pending base pool"
    );
    lc.assertEqualBN(
      offerInfo.offer.gives.sub(ethers.utils.parseUnits("100", 6)),
      pendingQuote,
      "Residual was not added to pending quote pool"
    );

    // second market order should produce the same effect (best has changed because old best was not able to repost)
    best = await mgv.best(usdc.address, wEth.address);
    offerInfo = await mgv.offerInfo(usdc.address, wEth.address, best);

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("100", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );

    let [pendingBase_, pendingQuote_] = await makerContract.get_pending();
    lc.assertEqualBN(
      pendingBase.add(takerGave),
      pendingBase_,
      "TakerGave was not added to pending base pool"
    );
    lc.assertEqualBN(
      offerInfo.offer.gives
        .sub(ethers.utils.parseUnits("100", 6))
        .add(pendingQuote),
      pendingQuote_,
      "Residual was not added to pending quote pool"
    );

    // putting density back to normal
    tx = await mgv.setDensity(usdc.address, wEth.address, 100);
    await tx.wait();
    tx = await mgv.setDensity(wEth.address, usdc.address, 100);
    await tx.wait();

    // Offer 3 and 4 were unable to repost so they should be out of the book
    let [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [2, -3, -4, -5, -6, 0, 0, -8, -7, -1]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 0, 0, 6, 1, 2, 3, 4, 5, 7]
    );

    // this market order should produce the following observables:
    // - offer 2 is now going to repost its residual which will be augmented with the content of the USDC pending pool
    // - the dual offer of offer 2 will be created with id 8 and will offer takerGave + the content of the WETH pending pool
    // - both pending pools should be empty

    let oldOffer2 = (await mgv.offerInfo(usdc.address, wEth.address, 2)).offer;

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("100", 6), // wants
      ethers.utils.parseEther("1"), // gives
      true
    );

    [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [2, -3, -4, -5, -6, 0, 0, -8, -7, -1]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 8, 0, 6, 1, 2, 3, 4, 5, 7]
    );

    let [pendingBase__, pendingQuote__] = await makerContract.get_pending();
    lc.assertEqualBN(pendingBase__, 0, "Pending base pool should be empty");
    lc.assertEqualBN(pendingQuote__, 0, "Pending quote pool should be empty");
    best = await mgv.best(wEth.address, usdc.address);
    let offer8 = (await mgv.offerInfo(wEth.address, usdc.address, best)).offer;
    assert(best == 8, "Best offer on WETH,USDC offer list should be #8");

    lc.assertEqualBN(
      offer8.gives,
      takerGave.add(pendingBase_),
      "Incorrect offer gives"
    );

    let offer2 = (await mgv.offerInfo(usdc.address, wEth.address, 2)).offer;
    lc.assertEqualBN(
      offer2.gives,
      pendingQuote_.add(oldOffer2.gives.sub(ethers.utils.parseUnits("100", 6))),
      "Incorrect offer gives"
    );
  });

  it("Test kill", async function () {
    await makerContract.pause();
    // taking all bids
    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("2500", 6), // wants
      ethers.utils.parseEther("1.5"), // gives
      true
    );
    assert(
      takerGot.eq(0) && takerGave.eq(0),
      "Start is not reneging on trades"
    );
    const [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [-2, -3, -4, -5, -6, 0, 0, -8, -7, -1]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, 8, 0, 6, 1, 2, 3, 4, 5, 7]
    );
  });

  it("Test restart at fixed shift", async function () {
    let tx = await makerContract.restart();
    await tx.wait();

    await init(
      NSLOTS,
      makerContract,
      ethers.utils.parseUnits("500", 6),
      ethers.utils.parseEther("0.15")
    );

    // book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    // console.log("===bids===");
    // await lc.logOrderBook(book, usdc, wEth);
    // book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    // console.log("===asks===");
    // await lc.logOrderBook(book, wEth, usdc);

    const [bids, asks] = await makerContract.get_offers(false);
    await checkOB(
      "OB bids",
      mgv,
      usdc.address,
      wEth.address,
      bids,
      [2, 3, 4, 5, 6, 0, 0, -8, -7, -1]
    );
    await checkOB(
      "OB asks",
      mgv,
      wEth.address,
      usdc.address,
      asks,
      [0, -8, 0, -6, -1, 2, 3, 4, 5, 7]
    );
  });
});
