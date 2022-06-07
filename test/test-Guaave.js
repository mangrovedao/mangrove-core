const { assert } = require("chai");
const { existsSync } = require("fs");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const lc = require("../lib/libcommon.js");

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
  let sourcer = null;

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
    // sets fee to 30
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
      value: prov.mul(20),
    });
    await fundTx.wait();
  });

  it("Deploy AAVE sourcer", async function () {
    const SourcerFactory = await ethers.getContractFactory("AaveSourcer");
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
    await lc.fund([
      ["WETH", "17.0", sourcer.address],
      ["USDC", "50000", sourcer.address],
    ]);
    let txs = [];
    let i = 0;
    txs[i++] = await sourcer.approveLender(wEth.address); // to mint awETH
    txs[i++] = await sourcer.approveLender(usdc.address); // to mint aUSDC
    txs[i++] = await sourcer.supply(
      wEth.address,
      ethers.utils.parseEther("17")
    );
    txs[i++] = await sourcer.supply(
      usdc.address,
      ethers.utils.parseUnits("50000", 6)
    );
    txs[i++] = await makerContract.set_liquidity_sourcer(sourcer.address);
    await lc.synch(txs);
    await lc.logLenderStatus(
      sourcer,
      "aave",
      ["WETH", "USDC"],
      sourcer.address
    );
    //console.log("Sourcer balance of awETH on aave: ", ethers.utils.formatEther(await sourcer.balance(wEth.address)));
    //console.log("Sourcer balance of aUSDC on aave: ", ethers.utils.formatUnits(await sourcer.balance(usdc.address),6));
  });

  it("Initialize", async function () {
    await init(
      NSLOTS,
      makerContract,
      ethers.utils.parseUnits("1000", 6),
      ethers.utils.parseEther("0.3")
    );
  });

  it("Market order", async function () {
    await wEth.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    const awETHBalance = await sourcer.balance(wEth.address);
    const aUSDCBalance = await sourcer.balance(usdc.address);

    let [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "WETH", // outbound
      "USDC", // inbound
      ethers.utils.parseEther("0.5"), // wants
      ethers.utils.parseUnits("3000", 6) // gives
    );
    await lc.logLenderStatus(
      sourcer,
      "aave",
      ["WETH", "USDC"],
      sourcer.address
    );
    lc.assertEqualBN(
      takerGot,
      lc.netOf(ethers.utils.parseEther("0.5"), 30),
      "incorrect taker got"
    );
    assert(bounty.eq(0), "incorrect bounty");
    lc.assertAlmost(
      awETHBalance.sub(ethers.utils.parseEther("0.5")), //maker pays before Mangrove fees
      await sourcer.balance(wEth.address),
      18,
      9,
      "incorrect WETH balance on aave"
    );
    lc.assertAlmost(
      aUSDCBalance.add(takerGave),
      await sourcer.balance(usdc.address),
      6,
      4,
      "incorrect USDC balance on aave"
    );
  });
});
