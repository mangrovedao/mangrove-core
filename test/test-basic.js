const { assert } = require("chai");
//const { parseToken } = require("ethers/lib/utils");
const { ethers, env, mangrove, network } = require("hardhat");
const lc = require("../lib/libcommon.js");
const chalk = require("chalk");

let testSigner = null;

function Big(x) {
  return lc.Big(x);
}

describe("Running tests...", function () {
  this.timeout(200_000); // Deployment is slow so timeout is increased
  let mgv = null;
  let dai = null;
  let usdc = null;

  before(async function () {
    // fetches all token contracts
    dai = await lc.getContract("DAI");
    usdc = await lc.getContract("USDC");

    // setting testRunner signer
    [testSigner] = await ethers.getSigners();

    // deploying mangrove and opening WETH/USDC market.
    mgv = await lc.deployMangrove();
    await lc.activateMarket(mgv, dai.address, usdc.address);
  });

  it("Basic offer", async function () {
    // Provisioning mangrove
    const MgvOffer = await ethers.getContractFactory("Basic");

    // Listenning to Credid events from Mangrove
    const filter_Credit = mgv.filters.Credit();
    let creditEvents = 0;
    mgv.on(filter_Credit, (maker, amount, event) => {
      creditEvents++;
      console.log(
        "Crediting",
        maker,
        "for",
        lc.formatToken(amount, 18),
        "ethers"
      );
      if (creditEvents == 2) {
        mgv.removeAllListeners();
      }
    });

    // deploying strat
    const makerContract = await MgvOffer.deploy(mgv.address);

    // // Listening
    // const filter_Fail = makerContract.filters.PosthookFail();
    // makerContract.once(
    //   filter_Fail,
    //   (outbound_tkn, inbound_tkn, offerId, message, event) => {
    //     console.log("Posthook failed with ", message);
    //   }
    // );

    const makerWants = lc.parseToken("1000", await usdc.decimals());
    const makerGives = lc.parseToken("1000", await dai.decimals());
    const gasreq = await makerContract.OFR_GASREQ();
    await mgv.setGasprice(20);
    const bounty = await makerContract.getMissingProvision(
      dai.address,
      usdc.address,
      gasreq,
      Big(0),
      Big(0)
    );
    const overrides = { value: bounty };
    // provision makerContract
    await mgv["fund(address)"](makerContract.address, overrides);
    // gives 1000 DAI (for offer) and 2 ETH (for refilling) to makerContract
    await lc.fund([
      ["DAI", "1000", makerContract.address],
      ["USDC", "1000", testSigner.address],
      ["ETH", "2.0", makerContract.address],
    ]);
    // bal should be 2.0
    let bal = await ethers.provider.getBalance(makerContract.address);
    lc.assertEqualBN(bal, lc.parseToken("2", 18), "Incorrect balance");
    // prov should be bounty
    let prov = await mgv.balanceOf(makerContract.address);
    lc.assertEqualBN(prov, bounty, "Incorrect provision");
    // approve dai for Mangrove
    await makerContract.approveMangrove(
      dai.address,
      ethers.constants.MaxUint256
    );
    // approve usdc for taker
    await usdc
      .connect(testSigner)
      .approve(mgv.address, ethers.constants.MaxUint256);
    await lc.newOffer(
      mgv,
      makerContract,
      "DAI",
      "USDC",
      makerWants,
      makerGives
    );
    // prov should now be 0.0
    prov = await mgv.balanceOf(makerContract.address);
    lc.assertEqualBN(prov, Big(0), "Incorrect provision");

    await mgv.setGasprice(50);

    // bounty2 should be higher than bounty
    const bounty2 = await makerContract.getMissingProvision(
      dai.address,
      usdc.address,
      gasreq,
      Big(0),
      Big(0)
    );

    const [takerGot, takerGave] = await lc.snipeSuccess(
      mgv,
      "DAI",
      "USDC",
      1,
      lc.parseToken("900", 18),
      lc.parseToken("900", 6)
    );

    const balDai = await dai.balanceOf(makerContract.address);
    const balUsdc = await usdc.balanceOf(makerContract.address);

    console.log(
      "Taker gave (USDC): ",
      chalk.red(lc.formatToken(takerGave, 6)),
      "Taker got (DAI): ",
      chalk.green(lc.formatToken(takerGot, 18))
    );
    console.log(
      "Maker has left (DAI):",
      chalk.blue(lc.formatToken(balDai, 18)),
      "Maker has now (USDC):",
      chalk.blue(lc.formatToken(balUsdc, 6))
    );
  });
});

// const usdc_decimals = await usdc.decimals();
// const filter_PosthookFail = mgv.filters.PosthookFail();
// mgv.once(filter_PosthookFail, (
//   outbound_tkn,
//   inbound_tkn,
//   offerId,
//   makerData,
//   event) => {
//     let outSym;
//     let inSym;
//     if (outbound_tkn == wEth.address) {
//       outSym = "WETH";
//       inSym = "USDC";
//     } else {
//       outSym = "USDC";
//       inSym = "WETH";
//     }
//     console.log(`Failed to repost offer #${offerId} on (${outSym},${inSym}) Offer List`);
//     console.log(ethers.utils.parseBytes32String(makerData));
//   }
// );
// const filter_MangroveFail = mgv.filters.OfferFail();
// mgv.once(filter_MangroveFail, (
//   outbound_tkn,
//   inbound_tkn,
//   offerId,
//   taker_address,
//   takerWants,
//   takerGives,
//   statusCode,
//   makerData,
//   event
//   ) => {
//     let outDecimals;
//     let inDecimals;
//     if (outbound_tkn == wEth.address) {
//       outDecimals = 18;
//       inDecimals = usdc_decimals;
//     } else {
//       outTkn = usdc_decimals;
//       inTkn = 18;
//     }
//   console.warn("Contract failed to execute taker order. Offer was: ", outbound_tkn, inbound_tkn, offerId);
//   console.warn("Order was ",
//   lc.formatToken(takerWants, outDecimals),
//   lc.formatToken(takerGives, inDecimals)
//   );
//   console.warn(ethers.utils.parseBytes32String(statusCode));
// });
// const filterContractLiquidity = makerContract.filters.NotEnoughLiquidity();
// makerContract.once(filterContractLiquidity, (outbound_tkn, missing, event) => {
//   let outDecimals;
//   let symbol;
//   if (outbound_tkn == wEth.address) {
//     outDecimals = 18;
//     symbol = "WETH";
//   } else {outDecimals = usdc_decimals; symbol = "USDC";}
//   console.warn ("could not fetch ",lc.formatToken(missing,outDecimals),symbol);
// }
// );

// const filterContractRepay = makerContract.filters.ErrorOnRepay();
// makerContract.once(filterContractRepay, (inbound_tkn, toRepay, errCode, event) => {
//   let inDecimals;
//   let symbol;
//   if (inbound_tkn == wEth.address) {
//     inDecimals = 18;
//     symbol = "WETH";
//   } else {inDecimals = usdc_decimals; symbol = "USDC";}
//   console.warn ("could not repay ",lc.formatToken(toRepay,inDecimals),symbol);
//   console.warn (errCode.toString());
// });
