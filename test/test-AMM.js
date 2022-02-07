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
    const NSLOTS = 100;
  
    // deploying strat
    const makerContract = (
      await Strat.deploy(
        mgv.address, 
        wEth.address, // base
        usdc.address, // quote
        ethers.utils.parseEther("1"), // BASE0
        ethers.utils.parseUnits("3000", 6), // QUOTE0
        NSLOTS // price slots
      )
    ).connect(testSigner);
    assert(!await makerContract.is_initialized(),"Contract should not be initialized");
    await makerContract.fundMangrove({value:lc.parseToken("10",18)});
    let pivotIds = new Array(NSLOTS);  
    pivotIds = pivotIds.fill(0,0);

    const receipt = await makerContract.initialize(
      lc.parseToken("100", 6), // quote progression
      NSLOTS/2, // NSLOTS/2 bids
      [pivotIds,pivotIds]
    );
    console.log(`Contract initialized, ${(await receipt.wait()).gasUsed} gas used`);
    let book = await reader.offerList(usdc.address, wEth.address, 0, NSLOTS);
    console.log("===bids===")
    await lc.logOrderBook(book, usdc, wEth);
    book = await reader.offerList(wEth.address, usdc.address, 0, NSLOTS);
    console.log("===asks===")
    await lc.logOrderBook(book, wEth, usdc);

    await makerContract.approveMangrove(wEth.address, ethers.constants.MaxUint256);
    await makerContract.approveMangrove(usdc.address, ethers.constants.MaxUint256);

  });
});    