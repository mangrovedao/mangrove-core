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
  
  before(async function () {
    // fetches all token contracts
    wEth = await lc.getContract("WETH");
    usdc = await lc.getContract("USDC");

    // setting testRunner signer
    [testSigner] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    [mgv, reader] = await lc.deployMangrove();
    await lc.activateMarket(mgv, wEth.address, usdc.address);
  });

  it("Deploy strat", async function () {
    //    lc.listenMgv(mgv);

    const strategy = "DAMM";
    const Strat = await ethers.getContractFactory(strategy);

    // deploying strat
    init_price = lc.parseToken("3000",6); // 1 eth = 3000 USDC (6 decimals)
    const makerContract = (
      await Strat.deploy(
        mgv.address, 
        wEth.address, // base
        usdc.address, // quote
        init_price,
        10 // 10 price slots
      )
    ).connect(testSigner);
    assert(!await makerContract.is_initialized(),"Contract should not be initialized");
    await makerContract.fundMangrove({value:lc.parseToken("2",18)});
    let pivotIds = [0,0,0,0,0,0,0,0,0,0];
    await makerContract.initialize(
      lc.parseToken("1",18), // each offer is on 1 ether volume
      lc.parseToken("0.01",18), // parameter for the price increment (default is arithmetic progression)
      ethers.BigNumber.from(5), // `nbids <= NSLOTS`. Says how many bids should be placed
      [pivotIds,pivotIds]
    );
    let book = await reader.offerList(usdc.address, wEth.address, 0, 10);
    console.log("===bids===")
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, 10);
    console.log("===asks===")
    await lc.logOrderBook(book, wEth, usdc);
  });
});    