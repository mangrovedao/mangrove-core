const { assert } = require("chai");
const { lstat } = require("fs");
const { ethers } = require("hardhat");
const lc = require("lib/libcommon.js");
const { listenMgv, parseToken, listenERC20 } = require("../lib/libcommon");

const { execTraderStrat } = require("./Exec/lenderStrats");

let testSigner = null;

async function deployStrat(strategy, mgv) {
  const dai = (await lc.getContract("DAI")).connect(testSigner);
  const wEth = (await lc.getContract("WETH")).connect(testSigner);
  const comp = (await lc.getContract("COMP")).connect(testSigner);
  const aave = (await lc.getContract("AAVE")).connect(testSigner); //returns addressesProvider
  const cwEth = (await lc.getContract("CWETH")).connect(testSigner);
  const cDai = (await lc.getContract("CDAI")).connect(testSigner);
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null, null]; // market pair for lender
  let enterMarkets = true;
  let router = null;
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
      makerContract = await Strat.deploy(
        comp.address,
        mgv.address,
        wEth.address,
        testSigner.address
      );
      makerContract = makerContract.connect(testSigner);
      market = [cwEth.address, cDai.address];
      break;
    case "SimpleAaveRetail":
    case "AdvancedAaveRetail":
      makerContract = await Strat.deploy(
        mgv.address,
        aave.address,
        testSigner.address
      );
      makerContract = makerContract.connect(testSigner);
      market = [wEth.address, dai.address];
      // aave rejects market entering if underlying balance is 0 (will self enter at first deposit)
      enterMarkets = false;
      let router_address = await makerContract.router();
      const RouterFactory = await ethers.getContractFactory("AaveDeepRouter");
      router = RouterFactory.attach(router_address);
      break;
    default:
      console.warn("Undefined strategy " + strategy);
  }
  await makerContract.deployed();

  // provisioning Mangrove on behalf of MakerContract
  let overrides = { value: parseToken("2.0", 18) };
  tx = await mgv["fund(address)"](makerContract.address, overrides);
  await tx.wait();

  lc.assertEqualBN(
    await mgv.balanceOf(makerContract.address),
    parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );

  // testSigner approves Mangrove for WETH/DAI before trying to take offers
  tkrTx = await wEth.approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();
  // taker approves mgv for DAI erc
  tkrTx = await dai.approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  let allowed = await wEth.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");
  allowed = await dai.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

  /*********************** MAKER SIDE PREMICES **************************/
  let mkrTxs = [];
  let i = 0;
  // offer should get/put base/quote tokens on lender contract (OK since `testSigner` is MakerContract admin)
  if (enterMarkets) {
    mkrTxs[i++] = await makerContract.enterMarkets(market);
  }

  // testSigner asks MakerContract to approve Mangrove for base (DAI/WETH)
  mkrTxs[i++] = await makerContract.approveMangrove(
    dai.address,
    ethers.constants.MaxUint256
  );
  mkrTxs[i++] = await makerContract.approveMangrove(
    wEth.address,
    ethers.constants.MaxUint256
  );
  mkrTxs[i++] = await makerContract.approveRouter(dai.address);
  mkrTxs[i++] = await makerContract.approveRouter(wEth.address);
  // One sends 1000 DAI to makerContract
  mkrTxs[i++] = await dai.transfer(
    makerContract.address,
    parseToken("1000.0", await lc.getDecimals("DAI"))
  );
  // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
  mkrTxs[i++] = await router.approveLender(market[0]);
  // NB in the special case of cEth this is only necessary to repay debt
  mkrTxs[i++] = await router.approveLender(market[1]);
  // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
  // overlyings are placed into reserve
  await lc.synch(mkrTxs);

  const supplyTx = await router.supply(
    market[1],
    await makerContract.reserve(),
    parseToken("900.0", await lc.getDecimals("DAI")),
    makerContract.address // from
  );
  const receipt = await supplyTx.wait();
  console.log("Supply cost", receipt.gasUsed.toNumber());
  return [makerContract, router];
}

/// start with 900 DAIs on lender and 100 DAIs locally
/// newOffer: wants 0.15 ETHs for 300 DAIs
/// taker snipes (full)
/// now 700 DAIs on lender, 0 locally and 0.15 ETHs
/// newOffer: wants 380 DAIs for 0.2 ETHs
/// borrows 0.05 ETHs using 1080 DAIs of collateral
/// now 1080 DAIs - locked DAI and 0 ETHs (borrower of 0.05 ETHs)
/// newOffer: wants 0.63 ETHs for 1500 DAIs
/// repays the full debt and borrows the missing part in DAI

describe("Deploy strategies", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let reader = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    [testSigner] = await ethers.getSigners();

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
      parseToken("10000.0", await lc.getDecimals("DAI")),
      "Minting DAI failed"
    );
    lc.assertEqualBN(
      wethBal,
      parseToken("10.0", await lc.getDecimals("WETH")),
      "Minting WETH failed"
    );

    [mgv, reader] = await lc.deployMangrove();
    //listenMgv(mgv);
    await lc.activateMarket(mgv, dai.address, wEth.address);
    let [, local] = await mgv.configInfo(dai.address, wEth.address);
    assert(local.active, "Market is inactive");
  });

  // it("Lender/borrower strat on compound", async function () {
  //   const makerContract = await deployStrat(
  //     "AdvancedCompoundRetail",
  //     mgv,
  //     testSigner.address
  //   );
  //   await execTraderStrat(makerContract, mgv, reader, "compound");
  // });

  it("Lender/borrower strat on aave", async function () {
    const [makerContract, router] = await deployStrat(
      "AdvancedAaveRetail",
      mgv,
      testSigner.address
    );
    await execTraderStrat(makerContract, router, mgv, reader, "aave");
    // lc.stopListeners([mgv]);
  });
});
