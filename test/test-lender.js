const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("lib/libcommon.js");
const chalk = require("chalk");
// const config = require ("config");
// const url = config.hardhat.networks.hardhat.forking.url;
// const blockNumber = config.hardhat.networks.hardhat.forking.blockNumber;

let testSigner = null;
const zero = lc.parseToken("0.0", 18);

async function deployStrat(strategy, mgv) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");
  const comp = await lc.getContract("COMP");
  const aave = await lc.getContract("AAVE"); //returns addressesProvider
  const cwEth = await lc.getContract("CWETH");
  const cDai = await lc.getContract("CDAI");
  const Strat = await ethers.getContractFactory(strategy);
  let makerContract = null;
  let market = [null, null]; // market pair for lender
  let enterMarkets = true;
  switch (strategy) {
    case "SimpleCompoundRetail":
    case "AdvancedCompoundRetail":
      makerContract = await Strat.deploy(
        comp.address,
        mgv.address,
        wEth.address
      );
      market = [cwEth.address, cDai.address];
      break;
    case "SimpleAaveRetail":
    case "AdvancedAaveRetail":
      makerContract = await Strat.deploy(aave.address, mgv.address);
      market = [wEth.address, dai.address];
      // aave rejects market entering if underlying balance is 0 (will self enter at first deposit)
      enterMarkets = false;
      break;
    default:
      console.warn("Undefined strategy " + strategy);
  }
  await makerContract.deployed();

  // provisioning Mangrove on behalf of MakerContract
  let overrides = { value: lc.parseToken("2.0", 18) };
  tx = await mgv["fund(address)"](makerContract.address, overrides);
  await tx.wait();

  lc.assertEqualBN(
    await mgv.balanceOf(makerContract.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );

  // testSigner approves Mangrove for WETH/DAI before trying to take offers
  tkrTx = await wEth
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();
  // taker approves mgv for DAI erc
  tkrTx = await dai
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);
  await tkrTx.wait();

  allowed = await wEth.allowance(testSigner.address, mgv.address);
  lc.assertEqualBN(allowed, ethers.constants.MaxUint256, "Approve failed");

  /*********************** MAKER SIDE PREMICES **************************/
  let mkrTxs = [];
  let i = 0;
  // offer should get/put base/quote tokens on lender contract (OK since `testSigner` is MakerContract admin)
  if (enterMarkets) {
    mkrTxs[i++] = await makerContract.connect(testSigner).enterMarkets(market);
  }

  // testSigner asks MakerContract to approve Mangrove for base (DAI/WETH)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveMangrove(dai.address, ethers.constants.MaxUint256);
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveMangrove(wEth.address, ethers.constants.MaxUint256);
  // One sends 1000 DAI to MakerContract
  mkrTxs[i++] = await dai
    .connect(testSigner)
    .transfer(
      makerContract.address,
      lc.parseToken("1000.0", await lc.getDecimals("DAI"))
    );
  // testSigner asks makerContract to approve lender to be able to mint [c/a]Token
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveLender(market[0], ethers.constants.MaxUint256);
  // NB in the special case of cEth this is only necessary to repay debt
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .approveLender(market[1], ethers.constants.MaxUint256);
  // makerContract deposits some DAI on Lender (remains 100 DAIs on the contract)
  mkrTxs[i++] = await makerContract
    .connect(testSigner)
    .mint(market[1], lc.parseToken("900.0", await lc.getDecimals("DAI")));

  await lc.synch(mkrTxs);

  return makerContract;
}

async function execLenderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `newOffer` external function
  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", // base
    "WETH", // quote
    lc.parseToken("0.5", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
  );

  let [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("800.0", await lc.getDecimals("DAI")), // taker wants 0.8 DAI
    lc.parseToken("0.5", await lc.getDecimals("WETH")) // taker is ready to give up-to 0.5 WETH
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("800.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );

  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.4", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );

  // checking that MakerContract did put WETH on lender
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", lc.parseToken("200", await lc.getDecimals("DAI")), zero, 4],
    ["WETH", takerGave, zero, 8],
  ]);
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
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

async function execTraderStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.15", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("300.0", await lc.getDecimals("DAI")) // promised DAI (will need to borrow)
  );

  let [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("300", await lc.getDecimals("DAI")),
    lc.parseToken("0.15", await lc.getDecimals("WETH"))
  );
  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("300.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.15", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", lc.parseToken("700", await lc.getDecimals("DAI")), zero, 4],
    ["WETH", takerGave, zero, 8],
  ]);
  // testSigner asks MakerContract to approve Mangrove for base (weth)
  mkrTx2 = await makerContract
    .connect(testSigner)
    .approveMangrove(wEth.address, ethers.constants.MaxUint256);
  await mkrTx2.wait();

  offerId = await lc.newOffer(
    mgv,
    makerContract,
    "WETH", // base
    "DAI", //quote
    lc.parseToken("380.0", await lc.getDecimals("DAI")), // wants DAI
    lc.parseToken("0.2", await lc.getDecimals("WETH")) // promised WETH
  );

  [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "WETH",
    "DAI",
    offerId,
    lc.parseToken("0.2", await lc.getDecimals("WETH")), // wanted WETH
    lc.parseToken("380.0", await lc.getDecimals("DAI")) // giving DAI
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("0.2", await lc.getDecimals("WETH")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("380", await lc.getDecimals("DAI")),
    "Incorrect given amount"
  );

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    // dai_on_lender = (1080 * CF_DAI * price_DAI - 0.05 * price_ETH)/price_DAI
    ["WETH", zero, lc.parseToken("0.05", await lc.getDecimals("WETH")), 9],
  ]);

  offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.63", await lc.getDecimals("WETH")), // wants ETH
    lc.parseToken("1500", await lc.getDecimals("DAI")) // gives DAI
  );
  [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "DAI",
    "WETH",
    offerId,
    lc.parseToken("1500", await lc.getDecimals("DAI")), // wanted DAI
    lc.parseToken("0.63", await lc.getDecimals("WETH")) // giving WETH
  );
  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("1500", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );
  lc.assertEqualBN(
    takerGave,
    lc.parseToken("0.63", await lc.getDecimals("WETH")),
    "Incorrect given amount"
  );
  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  //TODO check borrowing DAIs and not borrowing WETHs anymore
}

describe("Deploy strategies", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;

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
      lc.parseToken("10000.0", await lc.getDecimals("DAI")),
      "Minting DAI failed"
    );
    lc.assertEqualBN(
      wethBal,
      lc.parseToken("10.0", await lc.getDecimals("WETH")),
      "Minting WETH failed"
    );

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, wEth.address);
    let [, local] = await mgv.reader.config(dai.address, wEth.address);
    assert(local.active, "Market is inactive");
  });

  it("Pure lender strat on compound", async function () {
    const makerContract = await deployStrat("SimpleCompoundRetail", mgv);
    await execLenderStrat(makerContract, mgv, "compound");
  });

  it("Lender/borrower strat on compound", async function () {
    const makerContract = await deployStrat("AdvancedCompoundRetail", mgv);
    await execTraderStrat(makerContract, mgv, "compound");
  });

  it("Pure lender strat on aave", async function () {
    const makerContract = await deployStrat("SimpleAaveRetail", mgv);
    await execLenderStrat(makerContract, mgv, "aave");
  });

  it("Lender/borrower strat on aave", async function () {
    const makerContract = await deployStrat("AdvancedAaveRetail", mgv);
    const filter_Fail = mgv.filters.OfferFail();
    mgv.on(
      filter_Fail,
      (
        outbound_tkn,
        inbound_tkn,
        offerId,
        taker,
        takerWants,
        takerGives,
        mgvData,
        event
      ) => {
        console.log(
          chalk.red(
            `Offer ${offerId} failed with`,
            ethers.utils.parseBytes32String(mgvData)
          )
        );
      }
    );
    const filter_Success = mgv.filters.OfferSuccess();
    mgv.on(
      filter_Success,
      (
        outbound_tkn,
        inbound_tkn,
        offerId,
        taker,
        takerWants,
        takerGives,
        event
      ) => {
        console.log(chalk.green(`Offer ${offerId} succeeded`));
      }
    );
    await execTraderStrat(makerContract, mgv, "aave");
    lc.stopListeners([mgv]);
  });
});
