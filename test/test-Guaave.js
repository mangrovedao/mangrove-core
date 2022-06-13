const { assert } = require("chai");
const { existsSync } = require("fs");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const lc = require("../lib/libcommon.js");

async function init(NSLOTS, makerContract, bidAmount, askAmount) {
  let slice = 5;
  let pivotIds = new Array(NSLOTS);
  let amounts = new Array(NSLOTS);
  pivotIds = pivotIds.fill(0, 0);
  amounts.fill(bidAmount, 0, NSLOTS / 2);
  amounts.fill(askAmount, NSLOTS / 2, NSLOTS);

  for (let i = 0; i < NSLOTS / slice; i++) {
    const tx = await makerContract.initialize(
      NSLOTS / 2 - 1, // starts asking at NSLOTS/2
      slice * i, // from
      slice * (i + 1), // to
      [pivotIds, pivotIds],
      amounts
    );
    const receipt = await tx.wait();
    console.log(
      `Offers [${slice * i},${slice * (i + 1)}[ initialized (${
        receipt.gasUsed
      } gas used)`
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
  let sourcer = null;

  const NSLOTS = 20;
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
    // sets fee to 30 so redirecting fees to mgv itself to avoid crediting maker
    await mgv.setVault(mgv.address);
    await lc.activateMarket(mgv, wEth.address, usdc.address);
    await lc.fund([
      ["WETH", "50.0", taker.address],
      ["USDC", "100000", taker.address],
    ]);
  });

  it("Deploy strat", async function () {
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
        delta, //quote progression
        maker.address // admin
      )
    ).connect(maker);

    //await makerContract.setGasreq(ethers.BigNumber.from(500000));
    const prov = await makerContract.getMissingProvision(
      wEth.address,
      usdc.address,
      await makerContract.OFR_GASREQ(),
      0,
      0
    );
    const fundTx = await mgv["fund(address)"](makerContract.address, {
      value: prov.mul(NSLOTS * 2),
    });
    await fundTx.wait();
    await lc.fund([["WETH", "17.0", makerContract.address]]);
  });

  it("Deploy buffered AAVE sourcer", async function () {
    const SourcerFactory = await ethers.getContractFactory(
      "BufferedAaveSourcer"
    );
    sourcer = await SourcerFactory.deploy(
      (
        await lc.getContract("AAVE")
      ).address,
      0, // referral code
      1, // interest rate mode -stable-
      makerContract.address,
      maker.address
    );
    // liquidity sourcer will pull funds from AAVE

    let txs = [];
    let i = 0;
    txs[i++] = await makerContract.set_liquidity_sourcer(
      sourcer.address,
      800000
    );
    txs[i++] = await sourcer.bind(makerContract.address); // allowing makerContract to pull from sourcer

    txs[i++] = await sourcer.approveLender(wEth.address); // to mint awETH
    txs[i++] = await sourcer.approveLender(usdc.address); // to mint aUSDC

    // putting ETH as collateral on AAVE
    txs[i++] = await sourcer.supply(
      wEth.address,
      ethers.utils.parseEther("17")
    );

    // borrowing USDC on collateral
    txs[i++] = await sourcer.borrow(
      usdc.address,
      ethers.utils.parseUnits("2000", 6)
    );
    // setting buffer to be twice the promised volume of an offer
    // txs[i++] = await sourcer.set_buffer(
    //   wEth.address,
    //   ethers.utils.parseEther("3")
    // );
    // txs[i++] = await sourcer.set_buffer(
    //   usdc.address,
    //   ethers.utils.parseUnits("2000", 6)
    // );

    await lc.synch(txs);
    await lc.logLenderStatus(
      sourcer,
      "aave",
      ["WETH", "USDC"],
      sourcer.address,
      makerContract.address
    );
  });

  it("Initialize", async function () {
    await init(
      NSLOTS,
      makerContract,
      ethers.utils.parseUnits("1000", 6),
      ethers.utils.parseEther("0.3")
    );
    let book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===");
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===");
    await lc.logOrderBook(book, wEth, usdc);
  });

  it("Market order with buffer", async function () {
    // lc.listenOfferLogic(false, makerContract);
    // lc.listenMgv(mgv);
    const takerWants = ethers.utils.parseEther("3");
    await wEth.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    const awETHBalance = await sourcer.balance(wEth.address);

    const receipt = await (
      await mgv.connect(taker).marketOrder(
        wEth.address,
        usdc.address,
        takerWants, // wants
        ethers.utils.parseUnits("100000", 6), // reaaaally wants
        true
      )
    ).wait();
    console.log(`Market order passed for ${receipt.gasUsed} gas units`);
    await lc.logLenderStatus(
      sourcer,
      "aave",
      ["WETH", "USDC"],
      sourcer.address,
      makerContract.address
    );
    lc.assertAlmost(
      awETHBalance.sub(takerWants), //maker pays before Mangrove fees
      await sourcer.balance(wEth.address),
      18,
      9, // decimals of precision
      "incorrect WETH balance on aave"
    );
  });
});
