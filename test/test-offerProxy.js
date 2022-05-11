const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("lib/libcommon.js");
const chalk = require("chalk");
const { execLenderStrat } = require("./Exec/lenderStrats");

// const config = require ("config");
// const url = config.hardhat.networks.hardhat.forking.url;
// const blockNumber = config.hardhat.networks.hardhat.forking.blockNumber;

async function deployStrat(mgv, reader, players) {
  const dai = await lc.getContract("DAI");
  const aDai = await lc.getContract("ADAI");

  const wEth = await lc.getContract("WETH");

  const aave = await lc.getContract("AAVE");
  const lendingPool = await lc.getContract("AAVEPOOL");
  const Strat = (await ethers.getContractFactory("OfferProxy")).connect(
    players.deployer.signer
  );

  // admin side premices
  let offerProxy = await Strat.deploy(aave.address, mgv.address);

  await offerProxy.deployed();
  // offerProxy needs to let lendingPool pull inbound tokens from it in order to mint
  let tx = await offerProxy
    .connect(players.deployer.signer)
    .approveLender(wEth.address, ethers.constants.MaxUint256);
  await tx.wait();

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
    .fundMangrove(overrides);
  // maker approves aDai (Dai is outbound) transfer so that offerProxy can pull them on demand
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

  // sanity check
  lc.assertEqualBN(
    await mgv.balanceOf(offerProxy.address),
    lc.parseToken("2.0", 18),
    "Failed to fund the Mangrove"
  );
  lc.assertEqualBN(
    await offerProxy.connect(players.maker.signer).balanceOnMangrove(),
    lc.parseToken("2.0", 18),
    "Failed to fund the user account"
  );

  /*********************** DEPLOYER SIDE PREMISES **************************/
  offerProxy = offerProxy.connect(players.deployer.signer);
  let depTxs = [];
  let j = 0;

  // admin of makerContract
  // deployer asks MakerContract to approve Mangrove for DAI --here the outbound token
  depTxs[j++] = await offerProxy.approveMangrove(dai.address);
  // depTxs[j++] = await offerProxy.approveMangrove(
  //   wEth.address,
  //   ethers.constants.MaxUint256
  // );
  // maker contract need to approve lender for dai and weth transfer to be able to mint (not used for now in put)
  // depTxs[j++] = await offerProxy.approveLender(
  //   dai.address,
  //   ethers.constants.MaxUint256
  // );
  // depTxs[j++] = await offerProxy.approveLender(
  //   wEth.address,
  //   ethers.constants.MaxUint256
  // );
  await lc.synch(depTxs);
  return offerProxy;
}

describe("Deploy offerProxy", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv;
  let reader;
  let players;
  let offerProxy;

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
    //listenMgv(mgv);

    await lc.activateMarket(mgv, dai.address, wEth.address);
    let [, local] = await mgv.configInfo(dai.address, wEth.address);
    assert(local.active, "Market is inactive");
  });

  // testing strat
  it("Offer proxy on aave", async function () {
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");
    offerProxy = await deployStrat(mgv, reader, players);
    await execLenderStrat(offerProxy, mgv, reader, "aave", players);
    // checking offer owner of offerId 1 (residual)
    const [nextId, offerIds, owners] = await offerProxy.offerOwners(
      reader.address,
      dai.address,
      wEth.address,
      0,
      2
    );
    for (const i in offerIds) {
      console.log(
        "offer",
        offerIds[i].toNumber(),
        "is owned by",
        chalk.gray(`${owners[i]}`)
      );
      assert(owners[i] == players.maker.address, "wrong offer owner");
    }
  });

  it("Clean revert", async function () {
    // check that getFail is emitted during offer logic posthook
    lc.listenOfferLogic(offerProxy, await offerProxy.OUTOFLIQUIDITY());
    const aDai = await lc.getContract("ADAI");
    const dai = await lc.getContract("DAI");
    const wEth = await lc.getContract("WETH");

    //cancelling maker approval for aDai transfer to makerContract
    await aDai.connect(players.maker.signer).approve(offerProxy.address, 0);

    let offerId = await lc.newOffer(
      mgv,
      reader,
      offerProxy.connect(players.maker.signer),
      "DAI", // outbound
      "WETH", // inbound
      lc.parseToken("0.5", await lc.getDecimals("WETH")), // required WETH
      lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
    );

    let [offer] = await mgv.offerInfo(dai.address, wEth.address, offerId);
    lc.assertEqualBN(
      offer.gives,
      lc.parseToken("1000.0", await lc.getDecimals("DAI")),
      "Offer was not correctly published"
    );
    let bounty = await lc.snipeFail(
      mgv.connect(players.taker.signer),
      reader,
      "DAI", // maker outbound
      "WETH", // maker inbound
      offerId,
      lc.parseToken("800.0", await lc.getDecimals("DAI")), // taker wants 800 DAI
      lc.parseToken("0.5", await lc.getDecimals("WETH")) // taker is ready to give up-to 0.5 WETH
    );
    assert(bounty.gt(0), "Bounty missing");
  });
});
