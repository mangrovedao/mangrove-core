const hre = require("hardhat");
const helper = require("../helper");
const { logOrderBook } = require("../../lib/libcommon");
const chalk = require("chalk");

function big(x) {
  return ethers.BigNumber.from(x);
}

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No OBFiller account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const mgvContracts = await helper.getMangrove();
  console.log(
    "Running script on Mangrove",
    chalk.gray(`(${mgvContracts.contract.address})`)
  );
  const mgv = mgvContracts.contract.connect(wallet);
  const persistentOffer = await hre.ethers.getContract("Reposting");

  const weth = helper.contractOfToken("wEth").connect(wallet);
  const dai = helper.contractOfToken("dai").connect(wallet);
  const usdc = helper.contractOfToken("usdc").connect(wallet);

  const tokenParams = [
    [weth, "wEth", 18, ethers.utils.parseEther("1")],
    [dai, "dai", 18, ethers.utils.parseEther("0.0002")],
    [usdc, "usdc", 6, ethers.utils.parseEther("0.0002")],
  ];

  for (const [outbound_tkn, outName, outDecimals, outTknInETH] of tokenParams) {
    for (const [inbound_tkn, inName, inDecimals, inTknInETH] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        console.log(
          `* Looking for persistent offers in the (${outName},${inName}) OfferList...`
        );
        const [id, offerIds, offers, offerDetails] =
          await mgvContracts.reader.offerList(
            outbound_tkn.address,
            inbound_tkn.address,
            ethers.BigNumber.from(0),
            ethers.BigNumber.from(3)
          );
        let targets = [];
        let cpt;
        for (const i in offerDetails) {
          if (offerDetails[i].maker == persistentOffer.address) {
            targets[cpt] = [
              offerIds[i],
              offers[i].gives,
              offers[i].wants,
              offerDetails[i].gasreq,
            ];
            cpt++;
          }
        }
        await mgv.snipes(
          outbound_tkn.address,
          inbound_tkn.address,
          targets,
          true
        );
        console.log(
          `Snipped ${targets} offers on offer list (${outName},${inName})`
        );
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
