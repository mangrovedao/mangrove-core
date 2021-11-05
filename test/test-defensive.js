const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("lib/libcommon.js");
const chalk = require("chalk");

async function execPriceFedStrat(makerContract, mgv, lenderName) {
  const dai = await lc.getContract("DAI");
  const wEth = await lc.getContract("WETH");

  //putting DAI on lender for contract
  await lc.fund([["DAI", "1000.0", makerContract.address]]);
  await makerContract.approveLender(dai.address, ethers.constants.MaxUint256);
  await makerContract.mint(dai.address, await lc.parseToken("1000", 18));
  await makerContract.approveMangrove(dai.address, ethers.constants.MaxUint256);
  await makerContract.approveMangrove(
    wEth.address,
    ethers.constants.MaxUint256
  );

  // to be able to put received WETH on lender
  await makerContract.approveLender(wEth.address, ethers.constants.MaxUint256);

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);

  // // posting new offer on Mangrove via the MakerContract `post` method
  // when offer is taken contract must have approved Mangrove for dai transfer

  let offerId = await lc.newOffer(
    mgv,
    makerContract,
    "DAI", //base
    "WETH", //quote
    lc.parseToken("0.2", await lc.getDecimals("WETH")), // required WETH
    lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
  );
  const filter_slippage = makerContract.filters.Slippage();
  makerContract.once(filter_slippage, (id, old_wants, new_wants, event) => {
    assert(
      id.eq(offerId),
      `Reneging on wrong offer Id (${id} \u2260 ${offerId})`
    );
    lc.assertEqualBN(old_wants, lc.parseToken("0.2", 18), "Invalid old price");
    assert(old_wants.lt(new_wants), "Invalid new price");
    console.log(
      "    " +
        chalk.green(`\u2713`) +
        chalk.grey(` Verified logged event `) +
        chalk.yellow(`(${event.event})`)
    );
    console.log();
  });

  // snipe should fail because offer will renege trade (price too low)
  await wEth
    .connect(testSigner)
    .approve(mgv.address, ethers.constants.MaxUint256);

  await lc.snipeFail(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("1000.0", await lc.getDecimals("DAI")), // taker wants 1000 DAI
    lc.parseToken("0.2", await lc.getDecimals("WETH")) // but 0.2. is not market price (should be >= 0,3334)
  );

  // new offer should have been put on the book with the correct price (same offer ID)
  let [takerGot, takerGave] = await lc.snipeSuccess(
    mgv,
    "DAI", // maker base
    "WETH", // maker quote
    offerId,
    lc.parseToken("900.0", await lc.getDecimals("DAI")),
    lc.parseToken("0.36", await lc.getDecimals("WETH"))
  );

  lc.assertEqualBN(
    takerGot,
    lc.netOf(lc.parseToken("900.0", await lc.getDecimals("DAI")), fee),
    "Incorrect received amount"
  );

  await lc.logLenderStatus(makerContract, lenderName, ["DAI", "WETH"]);
  const zero = lc.parseToken("0.0", 1);
  const hundred = lc.parseToken("100", 18);
  await lc.expectAmountOnLender(makerContract, lenderName, [
    ["DAI", hundred, zero, 4], // 100 DAI remaining
    ["WETH", takerGave, zero, 8], // should have received takerGave WETH
  ]);
}

describe("Deploy defensive strategies", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let oracle = null;

  before(async function () {
    // 1. mint (1000 dai, 1000 eth, 1000 weth) for testSigner
    // 2. activates (dai,weth) market
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    [testSigner] = await ethers.getSigners();

    await lc.fund([
      ["WETH", "10.0", testSigner.address],
      //["DAI", "10000.0", testSigner.address],
    ]);

    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, wEth.address);

    const SimpleOracle = await ethers.getContractFactory("SimpleOracle");
    const usdc = await lc.getContract("USDC"); // oracle base currency

    oracle = await SimpleOracle.deploy(usdc.address); // deploy an USD based-Oracle
    await oracle.deployed();
  });

  it("Price fed strat", async function () {
    const Strat = await ethers.getContractFactory("PriceFed");
    const aave = await lc.getContract("AAVE");
    const makerContract = await Strat.deploy(
      oracle.address,
      aave.address,
      mgv.address
    );
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    await makerContract.deployed();
    await makerContract.setSlippage(300); // 3% slippage allowed
    const oracle_decimals = await oracle.decimals();
    await oracle.setPrice(dai.address, lc.parseToken("1.0", oracle_decimals)); // sets DAI price to 1 USD (6 decimals)
    await oracle.setPrice(
      wEth.address,
      lc.parseToken("3000.0", oracle_decimals)
    );

    await execPriceFedStrat(makerContract, mgv, "aave");
  });
});
