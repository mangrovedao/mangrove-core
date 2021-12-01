const hre = require("hardhat");
const helper = require("../helper");
const { logOrderBook } = require("../../lib/libcommon");
const chalk = require("chalk");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );
  const offerProxy = (await hre.ethers.getContract("OfferProxy")).connect(
    wallet
  );
  const aave = helper.getAave();

  const mgvContracts = await helper.getMangrove();
  const weth = helper.contractOfToken("wEth");
  const dai = helper.contractOfToken("dai");
  const usdc = helper.contractOfToken("usdc");

  const tokenParams = [
    [weth, "wEth", 18, ethers.utils.parseEther("1")],
    [dai, "dai", 18, ethers.utils.parseEther("0.0002")],
    [usdc, "usdc", 6, ethers.utils.parseEther("0.0002")],
  ];

  const ofr_gasreq = await offerProxy.OFR_GASREQ();
  const ofr_gasprice = ethers.BigNumber.from(0);
  const ofr_pivot = ethers.BigNumber.from(0);

  const usdToNative = ethers.utils.parseEther("0.0002");

  // let overrides = { value: ethers.utils.parseEther("1.0") };
  // await mgv["fund(address)"](repostLogic.address, overrides);
  let provisioned;
  for (const [outbound_tkn, outName, outDecimals, outTknInETH] of tokenParams) {
    // maker approves aOutbound_tkn (OfferProxy needs to be able to mint when matched)
    await aave[outName]
      .connect(wallet)
      .approve(offerProxy.address, ethers.constants.MaxUint256);
    console.log(
      `* User`,
      chalk.gray(`${wallet.address}`),
      `approves OfferProxy`,
      chalk.gray(`${offerProxy.address}`),
      `for am-${outName} transfer`
    );

    for (const [inbound_tkn, inName, inDecimals, inTknInETH] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        const makerWants = ethers.utils
          .parseUnits("2000", inDecimals)
          .mul(usdToNative)
          .div(inTknInETH); // makerWants
        const makerGives = ethers.utils
          .parseUnits("2000", outDecimals)
          .mul(usdToNative)
          .div(outTknInETH); // makerGives

        if (!provisioned) {
          const provision = (
            await mgvContracts.reader.getProvision(
              outbound_tkn.address,
              inbound_tkn.address,
              ofr_gasreq,
              ofr_gasprice
            )
          ).mul(30);

          let overrides = { value: provision };
          const tx = await offerProxy.fundMangrove(wallet.address, overrides);
          await tx.wait();
          provisioned = true;
          console.log(
            `* User`,
            chalk.gray(`${wallet.address}`),
            `provisioned ${ethers.utils.formatUnits(
              provision,
              18
            )} MATICS on Mangrove (via OfferProxy)`
          );
        }
        const ofrTx = await offerProxy.newOffer(
          outbound_tkn.address, //e.g weth
          inbound_tkn.address, //e.g dai
          makerWants,
          makerGives,
          ofr_gasreq,
          ofr_gasprice,
          ofr_pivot
        );
        await ofrTx.wait();
        console.log(
          `* Posting a new offer on the (${outName},${inName}) Offer List`
        );
        await ofrTx.wait();
        const book = await mgvContracts.reader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(10)
        );
        logOrderBook(book, outbound_tkn, inbound_tkn);
      }
    }
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
