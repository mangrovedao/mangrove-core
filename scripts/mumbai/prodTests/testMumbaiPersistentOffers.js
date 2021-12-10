const hre = require("hardhat");
const helper = require("../../helper");
const lc = require("../../../lib/libcommon");
const chalk = require("chalk");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const mgv = await helper.getMangrove();
  const repostOffer = await hre.ethers.getContract("Reposting");

  const weth = helper.contractOfToken("wEth").connect(wallet);
  await weth.approve(mgv.contract.address, ethers.constants.MaxUint256);

  const dai = helper.contractOfToken("dai").connect(wallet);
  await dai.approve(mgv.contract.address, ethers.constants.MaxUint256);

  const usdc = helper.contractOfToken("usdc").connect(wallet);
  await usdc.approve(mgv.contract.address, ethers.constants.MaxUint256);

  const tokenParams = [
    [weth, "WETH", 18, ethers.utils.parseEther("1")],
    [dai, "DAI", 18, ethers.utils.parseEther("0.0003")],
    [usdc, "USDC", 6, ethers.utils.parseEther("0.0003")],
  ];

  for (const [outbound_tkn, outName, outDecimals] of tokenParams) {
    for (const [inbound_tkn, inName, inDecimals] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        const [, ids, offers, offerDetails] = await mgv.reader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(10)
        );

        for (const i in offers) {
          if (offerDetails[i].maker == repostOffer.address) {
            const [, takerGot, takerGave, bounty] = await mgv.contract
              .connect(wallet)
              .callStatic.snipes(
                outbound_tkn.address,
                inbound_tkn.address,
                [
                  [
                    ids[i],
                    offers[i].gives.div(10),
                    offers[i].wants.div(10),
                    offerDetails[i].gasreq,
                  ],
                ],
                true
              );
            if (takerGot.eq(0)) {
              console.log(
                chalk.red(`*`),
                `Sniping would cause offer ${ids[i]} from (${outName},${inName}) Offer List to fail`,
                `\t resulting in a bounty of ${ethers.utils.formatUnits(
                  bounty,
                  18
                )}`
              );
              const bal = await outbound_tkn.balanceOf(repostOffer.address);
              console.log(
                `Balance of offer is ${ethers.utils.formatUnits(
                  bal,
                  outDecimals
                )}`
              );
            }
            console.log(
              chalk.yellow(`*`),
              `Sniping reposting offer ${ids[i]} from (${outName},${inName}) Offer List`,
              `\t Got ${ethers.utils.formatUnits(
                takerGot,
                outDecimals
              )} and gave ${ethers.utils.formatUnits(takerGave, inDecimals)}`
            );
            const snipeTx = await mgv.contract
              .connect(wallet)
              .snipes(
                outbound_tkn.address,
                inbound_tkn.address,
                [
                  [
                    ids[i],
                    offers[i].gives.div(10),
                    offers[i].wants.div(10),
                    offerDetails[i].gasreq,
                  ],
                ],
                true
              );
            await snipeTx.wait();
            const [offer_] = await mgv.contract.offerInfo(
              outbound_tkn.address,
              inbound_tkn.address,
              ids[i]
            );
            const isLive = offer_.gives > 0;
            if (isLive) {
              console.log(chalk.green(`\u2713`), "Offer is still in the book");
            } else {
              console.log(
                chalk.red(`\u2716`),
                "Offer is no longer in the book"
              );
            }
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
