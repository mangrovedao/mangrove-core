const hre = require("hardhat");
const helper = require("../helper");
const { logOrderBook } = require("../../lib/libcommon");
const chalk = require("chalk");

async function main() {
  if (!process.env["MUMBAI_OBFILLER_PRIVATE_KEY"]) {
    console.error("No OBFiller account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_OBFILLER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const mgvContracts = await helper.getMangrove();
  console.log(
    "Running script on Mangrove",
    chalk.gray(`(${mgvContracts.contract.address})`)
  );
  const mgv = mgvContracts.contract.connect(wallet);

  const weth = helper.contractOfToken("wEth");
  const dai = helper.contractOfToken("dai");
  const usdc = helper.contractOfToken("usdc");

  const tokenParams = [
    [weth, "wEth", 18, ethers.utils.parseEther("1")],
    [dai, "dai", 18, ethers.utils.parseEther("0.0002")],
    [usdc, "usdc", 6, ethers.utils.parseEther("0.0002")],
  ];

  for (const [outbound_tkn, outName, outDecimals, outTknInETH] of tokenParams) {
    for (const [inbound_tkn, inName, inDecimals, inTknInETH] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        console.log(
          `* Looking for OBFiller offers in the (${outName},${inName}) OfferList...`
        );
        const [id, offerIds, offers, offerDetails] =
          await mgvContracts.reader.offerList(
            outbound_tkn.address,
            inbound_tkn.address,
            ethers.BigNumber.from(0),
            ethers.BigNumber.from(50)
          );
        await logOrderBook(
          [id, offerIds, offers, offerDetails],
          outbound_tkn,
          inbound_tkn
        );
        for (const i in offerDetails) {
          if (offerDetails[i].maker == wallet.address) {
            const provision = await mgv.callStatic.retractOffer(
              outbound_tkn.address,
              inbound_tkn.address,
              offerIds[i],
              true
            );
            const tx = await mgv.retractOffer(
              outbound_tkn.address,
              inbound_tkn.address,
              offerIds[i],
              true
            );
            await tx.wait();
            console.log(
              `* Offer`,
              chalk.gray(offerIds[i].toString()),
              `retracted, ${ethers.utils.formatUnits(
                provision,
                18
              )} was credited to OBFiller provisions`
            );
          }
        }
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
