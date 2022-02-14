const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("../lib/libcommon.js");
const chalk = require("chalk");
//const { Mangrove } = require("../../mangrove.js");

let testSigner = null;

const z = ethers.BigNumber.from(0);

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let reader = null;
  let usdc = null;
  let wEth = null;
  let maker = null;
  let taker = null;

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
    const strategy = "DAMM";
    const Strat = await ethers.getContractFactory(strategy);
    const NSLOTS = 10;
    // price increase is delta/BASE_0
    const delta = lc.parseToken("34", 6); //  (in quotes!)

    // deploying strat
    const makerContract = (
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

    await lc.fund([
      ["WETH", "17.0", makerContract.address],
      ["USDC", "50000", makerContract.address],
    ]);
    
    const prov = await makerContract.getMissingProvision(
      wEth.address,
      usdc.address,
      await makerContract.OFR_GASREQ(),
      0,
      0
    );

    await makerContract.fundMangrove({ value: prov.mul(200) });
    await makerContract.setGasreq(ethers.BigNumber.from(500000));

    let slice = NSLOTS / 2;
    let bidding = true;
    let pivotIds = new Array(slice);
    let amounts = new Array(slice);
    pivotIds = pivotIds.fill(0, 0);
    amounts.fill(ethers.utils.parseUnits("1000", 6),0);

    for (let i = 0; i < 2; i++) {
      if (i >= 1) {
        bidding = false;
      }
      console.log(`[${slice * i}-${slice * (i + 1)}[`);
      const receipt = await makerContract.initialize(
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

    let book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);

    await makerContract.approveMangrove(
      wEth.address,
      ethers.constants.MaxUint256
    );
    await makerContract.approveMangrove(
      usdc.address,
      ethers.constants.MaxUint256
    );

    await wEth.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    let [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "WETH", // outbound
      "USDC", // inbound
      ethers.utils.parseEther("0.5"), // wants
      ethers.utils.parseUnits("3000", 6) // gives
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

    book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);

    [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "USDC", // outbound
      "WETH", // inbound
      ethers.utils.parseUnits("3500", 6), // wants
      ethers.utils.parseEther("1.5") // gives
    );

    book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);

    console.log(chalk.yellow("Shifting"), chalk.red(-2));
    await makerContract.shift(-2);
    book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);

    console.log(chalk.yellow("Shifting"), chalk.green(6));
    await makerContract.shift(3);
    book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);
  });
});
