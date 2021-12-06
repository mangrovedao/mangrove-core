const hre = require("hardhat");
const helper = require("../helper");
const lc = require("../../lib/libcommon");
const { Mangrove } = require("@giry/mangrove.js");

async function main() {
  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    helper.getProvider()
  );
  const repostLogic = (await hre.ethers.getContract("Reposting")).connect(
    wallet
  );

  const MgvJS = await Mangrove.connect({
    provider: hre.network.config.url,
    signer: wallet,
  });
  // const { readOnly, signer } = await eth._createSigner(options); // returns a provider equipped signer
  // const network = await Eth.getProviderNetwork(signer.provider);

  const weth = MgvJS.token("WETH").contract;
  const dai = MgvJS.token("DAI").contract;
  const usdc = MgvJS.token("USDC").contract;

  MgvJS._provider.pollingInterval = 250;

  const tokenParams = [
    [dai, "DAI", MgvJS.getDecimals("DAI"), 0.0003],
    [weth, "WETH", MgvJS.getDecimals("WETH"), 1],
    [usdc, "USDC", MgvJS.getDecimals("USDC"), 0.0003],
  ];

  // const ofr_gasreq = ethers.BigNumber.from(200000);
  // const ofr_gasprice = ethers.BigNumber.from(0);
  // const ofr_pivot = ethers.BigNumber.from(0);

  const usdToNative = ethers.utils.parseUnits("0.0003", 18);

  const fundTx = await MgvJS.fund(repostLogic.address, 1);
  await fundTx.wait();

  for (const [
    outbound_tkn,
    outName,
    outDecimals,
    outTknInMatic,
  ] of tokenParams) {
    const tx = await repostLogic.approveMangrove(
      outbound_tkn.address,
      ethers.constants.MaxUint256
    );
    await tx.wait();

    for (const [inbound_tkn, inName, inDecimals, inTknInMatic] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        const mkr = await MgvJS.simpleMakerConnect({
          address: repostLogic.address,
          base: outName,
          quote: inName,
        });

        const transferTx = await outbound_tkn.transfer(
          repostLogic.address,
          MgvJS.toUnits(1000 * inTknInMatic, outName)
        );
        await transferTx.wait();
        console.log(
          `* Transferred ${
            1000 * inTknInMatic
          } ${outName} to persistent offer logic`
        );
        const { id: ofrId } = await mkr.newAsk({
          wants: 1000 * outTknInMatic,
          gives: 1000 * inTknInMatic,
        });

        console.log(
          `* Posting new persistent offer ${ofrId} on (${outName},${inName}) Market`
        );
        const book = await mgvContracts.reader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(3)
        );
        await lc.logOrderBook(book, outbound_tkn, inbound_tkn);
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
