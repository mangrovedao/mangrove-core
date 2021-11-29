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

async function deployStrat(mgv, players) {
  const dai = await lc.getContract("DAI");
  const aDai = await lc.getContract("ADAI");

  const wEth = await lc.getContract("WETH");

  const aave = await lc.getContract("AAVE");
  const lendingPool = await lc.getContract("AAVEPOOL");
  const Strat = (await ethers.getContractFactory("OfferProxy")).connect(
    players.deployer.signer
  );
  let offerProxy = await Strat.deploy(aave.address, mgv.address);

  await offerProxy.deployed();

  // Taker side premises
  // taker approves Mangrove for WETH (inbound) before trying to take offers
  const tkrTx = await wEth
    .connect(players.taker.signer)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  // Maker side premises
  let mkrTxs = [];
  let i;
  // provisioning Mangrove in case offer fails
  // NB: for multi user offers this has to be done via the contract and not direclty
  let overrides = { value: lc.parseToken("2.0", 18) };
  mkrTxs[i++] = await offerProxy
    .connect(players.maker.signer)
    .fundMangrove(players.maker.address, overrides);
  // sanity check
  lc.assertEqualBN(
    await mgv.balanceOf(offerProxy.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );
  lc.assertEqualBN(
    await offerProxy.mgvBalanceOf(players.maker.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the user account"
  );
  // maker approves takerProfit for aDai (Dai is outbound) transfer
  mkrTxs[i++] = await aDai
    .connect(players.maker.signer)
    .approve(offerProxy.address, ethers.constants.MaxUint256);
  // Maker mints 1000 aDai on AAVE
  mkrTxs[i++] = await dai
    .connect(players.maker.signer)
    .approve(lendingPool.address, ethers.constants.MaxUint256);
  mkrTxs[i++] = await lendingPool
    .connect(players.maker.signer)
    .deposit(dai.address, lc.parseToken("1000", 18), players.maker.address, 0);
  await lc.synch(mkrTxs);

  /*********************** DEPLOYER SIDE PREMICES **************************/
  offerProxy = offerProxy.connect(players.deployer.signer);
  let depTxs = [];
  let j = 0;

  // admin of makerContract
  // deployer asks MakerContract to approve Mangrove for DAI & WETH --here only DAI is needed
  depTxs[j++] = await offerProxy.approveMangrove(
    dai.address,
    ethers.constants.MaxUint256
  );
  depTxs[j++] = await offerProxy.approveMangrove(
    wEth.address,
    ethers.constants.MaxUint256
  );
  // maker contract need to approve lender for dai and weth transfer to be able to mint (during put)
  depTxs[j++] = await offerProxy.approveLender(
    dai.address,
    ethers.constants.MaxUint256
  );
  depTxs[j++] = await offerProxy.approveLender(
    wEth.address,
    ethers.constants.MaxUint256
  );
  await lc.synch(depTxs);
  return offerProxy;
}

describe("Deploy offerProxy", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv;
  let reader;
  let players;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    players = await lc.getAccounts();
    // Funding Maker (1000 DAI)
    // Funding Taker (1 WETH)
    let daiBal = await dai.balanceOf(players.maker.address);
    let wethBal = await wEth.balanceOf(players.taker.address);
    await lc.fund([
      ["WETH", "1.0", players.taker.address],
      ["DAI", "1000.0", players.maker.address],
    ]);
    daiBal = (await dai.balanceOf(players.maker.address)).sub(daiBal);
    wethBal = (await wEth.balanceOf(players.taker.address)).sub(wethBal);
    lc.assertEqualBN(
      daiBal,
      lc.parseToken("1000.0", await lc.getDecimals("DAI")),
      "Minting DAI failed"
    );
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("1.0", await lc.getDecimals("WETH")),
      "Minting WETH failed"
    );

    // Retrieving Mangrove contract and activting weth-dai market
    [mgv, reader] = await lc.deployMangrove();
    listenMgv(mgv);

    await lc.activateMarket(mgv, dai.address, wEth.address);
    let [, local] = await reader.config(dai.address, wEth.address);
    assert(local.active, "Market is inactive");
  });

  // testing strat
  it("Offer proxy on aave", async function () {
    let offerProxy = await deployStrat(mgv, players);
    await execLenderStrat(offerProxy, mgv, reader, "aave", players);
    lc.sleep(5000);
    lc.stopListeners([mgv]);
  });
});
