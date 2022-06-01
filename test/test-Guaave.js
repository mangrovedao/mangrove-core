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

async function logLender(makerContract) {
  await lc.logLenderStatus(
    makerContract,
    "aave",
    ["USDC", "WETH"],
    makerContract.address // account on lender
  );
}

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let usdc = null;
  let wEth = null;
  let aUsdc = null;
  let awEth = null;
  let maker = null;
  let taker = null;
  let makerContract = null;
  let lendingPool = null;

  const NSLOTS = 10;
  // price increase is delta/BASE_0
  const delta = lc.parseToken("34", 6); //  (in quotes!)

  before(async function () {
    // fetches all token contracts
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");
    awEth = await lc.getContract("AWETH");
    aUsdc = await lc.getContract("AUSDC");
    lendingPool = await lc.getContract("AAVEPOOL");

    // setting testRunner signer
    [maker, taker] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    [mgv, reader] = await lc.deployMangrove();
    await lc.activateMarket(mgv, wEth.address, usdc.address);

    // funding taker
    await lc.fund([
      ["WETH", "50.0", taker.address],
      ["USDC", "100000", taker.address],
    ]);
  });

  it("Deploy strat", async function () {
    //lc.listenMgv(mgv);
    const strategy = "Guaave";
    const Strat = await ethers.getContractFactory(strategy);
    const addressesProvider = await lc.getContract("AAVE");

    // deploying strat
    makerContract = (
      await Strat.deploy(
        mgv.address,
        wEth.address, // base
        usdc.address, // quote
        // Pmin = QUOTE0/BASE0
        {
          base_0: ethers.utils.parseEther("0.34"),
          quote_0: ethers.utils.parseUnits("1000", 6),
          nslots: NSLOTS,
          delta: delta,
        },
        {
          addressesProvider: addressesProvider.address,
          referralCode: 0,
          interestRateMode: 1, // Stable
        },
        maker.address // default treasury for base and quote
      )
    ).connect(maker);

    await (
      await makerContract.set_buffer(true, ethers.utils.parseEther("0.68"))
    ).wait();
    await (
      await makerContract.set_buffer(false, ethers.utils.parseUnits("2000", 6))
    ).wait();
    await (
      await makerContract.set_treasury(true, makerContract.address)
    ).wait();
    await (
      await makerContract.set_treasury(false, makerContract.address)
    ).wait();

    // maker is the EOA for quote and base treasury
    await lc.fund([
      ["WETH", "10.0", maker.address],
      ["USDC", "20000", maker.address],
    ]);

    // Maker mints aWETHs and aUSDCs on AAVE
    let mkrTxs = [];
    let i = 0;
    // approve lending pool to mint
    mkrTxs[i++] = await wEth
      .connect(maker)
      .approve(lendingPool.address, ethers.constants.MaxUint256);
    // approve makerContract to pay locally during trade
    mkrTxs[i++] = await wEth
      .connect(maker)
      .approve(makerContract.address, ethers.constants.MaxUint256);

    mkrTxs[i++] = await usdc
      .connect(maker)
      .approve(lendingPool.address, ethers.constants.MaxUint256);
    mkrTxs[i++] = await usdc
      .connect(maker)
      .approve(makerContract.address, ethers.constants.MaxUint256);

    // minting...
    mkrTxs[i++] = await lendingPool
      .connect(maker)
      .supply(wEth.address, lc.parseToken("9", 18), makerContract.address, 1);
    mkrTxs[i++] = await lendingPool
      .connect(maker)
      .supply(
        usdc.address,
        lc.parseToken("18000", 6),
        makerContract.address,
        1
      );
    await lc.synch(mkrTxs);

    lc.assertAlmost(
      lc.parseToken("18000", 6),
      await aUsdc.balanceOf(makerContract.address),
      6,
      5,
      "aUSDC not minted as expected"
    );
    lc.assertAlmost(
      lc.parseToken("9", 18),
      await awEth.balanceOf(makerContract.address),
      18,
      10, // 10 decimals precision
      "aWETH not minted as expected"
    );

    // provisioning Guaave on Mangrove
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

    // initiating Guaave on Mangrove
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

    let book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);
    await logLender(makerContract);
  });

  it("Market orders", async function () {
    // taker needs to approve mangrove to run market orders
    await wEth.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    //lc.listenOfferLogic(makerContract);
    //lc.listenMgv(mgv);
    let [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "WETH", // outbound
      "USDC", // inbound
      ethers.utils.parseEther("0.5"), // wants
      ethers.utils.parseUnits("3000", 6) // gives
    );
    await logLender(makerContract);

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

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("3500", 6), // wants
      ethers.utils.parseEther("1.5") // gives
    );
    await logLender(makerContract);

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

  it("Guaave repays first when borrowing", async function () {
    // sending all ETH on aave to taker acount
    const tx1 = await makerContract.redeem(
      usdc.address,
      ethers.constants.MaxUint256,
      taker.address
    );
    await tx1.wait();

    const tx2 = await makerContract.borrow(
      usdc.address,
      ethers.utils.parseUnits("5000", 6),
      makerContract.address
    );
    await tx2.wait();

    await logLender(makerContract);

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("3500", 6), // wants
      ethers.utils.parseEther("1.5") // gives
    );
    await logLender(makerContract);
  });
});
