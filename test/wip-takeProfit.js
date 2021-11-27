const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("lib/libcommon.js");
const chalk = require("chalk");
const { listenMgv, listenERC20 } = require("../lib/libcommon");
const { execLenderStrat } = require("./Exec/lenderStrats");

// const config = require ("config");
// const url = config.hardhat.networks.hardhat.forking.url;
// const blockNumber = config.hardhat.networks.hardhat.forking.blockNumber;

let testSigner = null;
let testRunner = null;
const zero = lc.parseToken("0.0", 18);

async function deployStrat(mgv) {
  const dai = (await lc.getContract("DAI")).connect(testSigner);
  const aDai = (await lc.getContract("ADAI")).connect(testSigner);

  const wEth = (await lc.getContract("WETH")).connect(testSigner);
  const awEth = (await lc.getContract("AWETH")).connect(testSigner);

  const aave = (await lc.getContract("AAVE")).connect(testSigner); //returns addressesProvider
  const lendingPool = (await lc.getContract("AAVEPOOL")).connect(testSigner);
  const Strat = await ethers.getContractFactory("TakeProfit");
  const takeProfit = (await Strat.deploy(aave.address, mgv.address)).connect(
    testSigner
  );
  await takeProfit.deployed();
  takeProfit.onBehalf = testRunner; // for logLenderStatus

  // provisioning Mangrove on behalf of MakerContract
  // NB: for multi user offers this has to be done via the contract and not direclty
  let overrides = { value: lc.parseToken("2.0", 18) };
  await takeProfit.fundMangrove(overrides);

  lc.assertEqualBN(
    await mgv.balanceOf(takeProfit.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );
  lc.assertEqualBN(
    await takeProfit.mgvBalanceOf(testRunner),
    lc.parseToken("2.0", 18),
    "Failed to fund the user account"
  );

  // testSigner approves Mangrove for WETH/DAI before trying to take offers
  tkrTx = await wEth.approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();
  // taker approves mgv for DAI erc
  tkrTx = await dai.approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  /*********************** MAKER SIDE PREMICES **************************/
  let mkrTxs = [];
  let i = 0;

  // testSigner asks MakerContract to approve Mangrove for base (DAI/WETH)
  mkrTxs[i++] = await takeProfit.approveMangrove(
    dai.address,
    ethers.constants.MaxUint256
  );
  mkrTxs[i++] = await takeProfit.approveMangrove(
    wEth.address,
    ethers.constants.MaxUint256
  );
  // takeProfit needs to pull aToken from user account
  mkrTxs[i++] = await aDai.approve(
    takeProfit.address,
    ethers.constants.MaxUint256
  );
  mkrTxs[i++] = await awEth.approve(
    takeProfit.address,
    ethers.constants.MaxUint256
  );

  // One deposits 1000 DAI on AAVE
  mkrTxs[i++] = await dai.approve(
    lendingPool.address,
    ethers.constants.MaxUint256
  );
  mkrTxs[i++] = await lendingPool.deposit(
    dai.address,
    lc.parseToken("1000", 18),
    testRunner,
    0
  );

  await lc.synch(mkrTxs);

  return takeProfit;
}

describe("Deploy takeProfit", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    [testSigner] = await ethers.getSigners();
    testRunner = await testSigner.getAddress();

    let daiBal = await dai.balanceOf(testSigner.address);
    let wethBal = await wEth.balanceOf(testSigner.address);
    await lc.fund([
      ["WETH", "10.0", testSigner.address],
      ["DAI", "10000.0", testSigner.address],
    ]);

    daiBal = (await dai.balanceOf(testSigner.address)).sub(daiBal);
    wethBal = (await wEth.balanceOf(testSigner.address)).sub(wethBal);

    lc.assertEqualBN(
      daiBal,
      lc.parseToken("10000.0", await lc.getDecimals("DAI")),
      "Minting DAI failed"
    );
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("10.0", await lc.getDecimals("WETH")),
      "Minting WETH failed"
    );

    mgv = await lc.deployMangrove();
    listenMgv(mgv);
    await lc.activateMarket(mgv, dai.address, wEth.address);
    let [, local] = await mgv.reader.config(dai.address, wEth.address);
    assert(local.active, "Market is inactive");
  });

  it("Take profit on aave", async function () {
    const takeprofit = await deployStrat(mgv);
    lc.listenOfferLogic(takeprofit, [
      "NewOffer",
      "ErrorOnRedeem",
      "ErrorOnMint",
      "UnkownOffer",
      "GetFail",
      "PutFail",
    ]);
    await execLenderStrat(takeprofit, mgv, "aave");
  });
});
