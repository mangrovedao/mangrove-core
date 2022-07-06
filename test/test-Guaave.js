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
      true,
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
  let aave_router = null;

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
        maker.address // reserve address is maker's wallet
      )
    ).connect(maker);
  });

  it("Deploy buffered AAVE router", async function () {
    // default router for Mango is `SimpleRouter` that uses `reserve` to pull and push liquidity
    // here we want to use aave for (il)liquidity and store liquid overlying at reserve
    // router will redeem and deposit funds that are mobilized during trade execution
    const RouterFactory = await ethers.getContractFactory("AaveRouter");
    aave_router = await RouterFactory.deploy(
      (
        await lc.getContract("AAVE")
      ).address,
      0, // referral code
      1 // interest rate mode -stable-
    );
    await aave_router.deployed();

    // liquidity router will pull funds from AAVE
    const bindTx = await aave_router.bind(makerContract.address);
    await bindTx.wait();

    let txs = [];
    let i = 0;

    txs[i++] = await makerContract.set_router(aave_router.address);
    txs[i++] = await makerContract.set_reserve(aave_router.address);
    await lc.synch(txs);
    // computing necessary provision (which has changed because of new router GAS_OVERHEAD)
    const prov = await makerContract.getMissingProvision(
      wEth.address,
      usdc.address,
      await makerContract.ofr_gasreq(),
      0,
      0
    );
    const fundTx = await mgv["fund(address)"](makerContract.address, {
      value: prov.mul(NSLOTS * 2),
    });
    await fundTx.wait();
    await lc.fund([["WETH", "17.0", makerContract.address]]);

    txs = [];
    i = 0;
    txs[i++] = await aave_router.approveLender(wEth.address); // to mint awETH
    txs[i++] = await aave_router.approveLender(usdc.address); // to mint aUSDC

    txs[i++] = await makerContract.approveRouter(wEth.address); // to allow router to pull/push from Mango
    txs[i++] = await makerContract.approveRouter(usdc.address);
    // putting ETH as collateral on AAVE
    txs[i++] = await aave_router.supply(
      wEth.address, //asset
      await makerContract.reserve(), // reserve
      ethers.utils.parseEther("17"), //amount
      makerContract.address // from (makerContract was funded above)
    );
    await lc.synch(txs);

    // borrowing USDC on collateral
    const borrowTx = await aave_router.borrow(
      usdc.address, // asset
      await makerContract.reserve(),
      ethers.utils.parseUnits("2000", 6),
      makerContract.address // (maker contract is buffer)
    );

    const receipt = await borrowTx.wait();
    console.log("Borrow gas cost", receipt.gasUsed.toNumber());

    await lc.logLenderStatus(
      aave_router,
      "aave",
      ["WETH", "USDC"],
      aave_router.address,
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

    const awETHBalance = await (
      await lc.getContract("AWETH")
    ).balanceOf(aave_router.address);

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
      aave_router,
      "aave",
      ["WETH", "USDC"],
      aave_router.address,
      makerContract.address
    );
    lc.assertAlmost(
      awETHBalance.sub(takerWants), //maker pays before Mangrove fees
      await (await lc.getContract("AWETH")).balanceOf(aave_router.address),
      18,
      9, // decimals of precision
      "incorrect WETH balance on aave"
    );
  });
});
