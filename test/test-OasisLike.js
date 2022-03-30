const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers } = require("hardhat");
const lc = require("../lib/libcommon.js");
const chalk = require("chalk");
//const { Mangrove } = require("../../mangrove.js");

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let reader = null;
  let usdc = null;
  let wEth = null;
  let maker = null;
  let taker = null;
  let makerContract = null;

  before(async function () {
    // fetches all token contracts
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");

    // setting testRunner signer
    [maker, taker] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    [mgv, reader] = await lc.deployMangrove();
    await lc.activateMarket(mgv, wEth.address, usdc.address);
    await lc.fund([["USDC", "3000", taker.address]]);
  });

  it("Deploy strat", async function () {
    const strategy = "OasisLike";
    const Strat = await ethers.getContractFactory(strategy);

    // deploying strat
    makerContract = await Strat.deploy(mgv.address);
    await makerContract.deployed();
    makerContract = makerContract.connect(maker);

    // funds come from deployer's wallet by default
    await lc.fund([["WETH", "0.5", maker.address]]);

    const prov = await makerContract.getMissingProvision(
      wEth.address,
      usdc.address,
      await makerContract.OFR_GASREQ(),
      0,
      0
    );
    await makerContract.fundMangrove({ value: prov });
  });

  it("Market orders", async function () {
    // makerContract approves mangrove for outbound token transfer
    // anyone can call this function
    await makerContract.approveMangrove(
      wEth.address,
      ethers.constants.MaxUint256
    );
    // since funds are in maker wallet, maker approves contract for outbound token transfer
    // this approval is also used for `depositToken` call
    await wEth
      .connect(maker)
      .approve(makerContract.address, ethers.constants.MaxUint256);

    // taker approves mangrove for inbound token transfer
    await usdc.connect(taker).approve(mgv.address, ethers.constants.MaxUint256);

    const ofrId = await lc.newOffer(
      mgv,
      reader,
      makerContract,
      "WETH",
      "USDC",
      ethers.utils.parseUnits("3000", 6),
      ethers.utils.parseEther("0.5")
    );

    let [takerGot, takerGave, bounty] = await lc.marketOrder(
      mgv.connect(taker),
      "WETH", // outbound
      "USDC", // inbound
      ethers.utils.parseEther("0.25"), // wants
      ethers.utils.parseUnits("1500", 6), // gives
      true
    );

    lc.assertEqualBN(
      bounty,
      ethers.utils.parseEther("0"),
      "Taker should not receive a bounty"
    );
    lc.assertEqualBN(
      takerGot,
      lc.netOf(ethers.utils.parseEther("0.25"), 30),
      "Incorrect received amount"
    );
    const [offer] = await mgv.offerInfo(wEth.address, usdc.address, ofrId);
    lc.assertEqualBN(
      offer.gives,
      ethers.utils.parseEther("0.25"),
      "Offer residual missing"
    );
  });
});
