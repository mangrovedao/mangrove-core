const hre = require("hardhat");
const helper = require("../helper");
const lc = require("../../lib/libcommon");
const { Mangrove } = require("../../../mangrove.js");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  // if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
  //   console.error("No tester account defined");
  // }

  // const walletDeployer = new ethers.Wallet(
  //   process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
  //   helper.getProvider()
  // );

  const repostLogic = await hre.ethers.getContract("Reposting");

  // const adminTx = await repostLogic.connect(walletDeployer).setAdmin(wallet.address);
  // await adminTx.wait();

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
    [dai, "DAI", MgvJS.getDecimals("DAI"), 1],
    [weth, "WETH", MgvJS.getDecimals("WETH"), 4287],
    [usdc, "USDC", MgvJS.getDecimals("USDC"), 1],
  ];

  // const ofr_gasreq = ethers.BigNumber.from(200000);
  // const ofr_gasprice = ethers.BigNumber.from(0);
  // const ofr_pivot = ethers.BigNumber.from(0);

  const fundTx = await MgvJS.fund(repostLogic.address, 1);
  await fundTx.wait();
  const overrides = { gasLimit: 200000 };
  const volume = 10000;

  for (const [outbound_tkn, outName, outDecimals, outTknInUSD] of tokenParams) {
    const tx = await repostLogic
      .connect(wallet)
      .approveMangrove(
        outbound_tkn.address,
        ethers.constants.MaxUint256,
        overrides
      );
    await tx.wait();

    for (const [inbound_tkn, inName, inDecimals, inTknInUSD] of tokenParams) {
      if (outbound_tkn.address != inbound_tkn.address) {
        const mkr = await MgvJS.MakerConnect({
          address: repostLogic.address,
          base: outName,
          quote: inName,
        });

        const transferTx = await outbound_tkn.transfer(
          repostLogic.address,
          MgvJS.toUnits(volume / outTknInUSD, outName),
          overrides
        );
        await transferTx.wait();
        console.log(
          `* Transferred ${
            volume / outTknInUSD
          } ${outName} to persistent offer logic`
        );
        // will hang if pivot ID not correctly evaluated
        const { id: ofrId } = await mkr.newAsk(
          {
            wants: (volume + 10) / inTknInUSD,
            gives: volume / outTknInUSD,
          },
          overrides
        );

        console.log(
          `* Posting new persistent offer ${ofrId} on (${outName},${inName}) Offer List`
        );
        const mgvContracts = await helper.getMangrove();
        const badReader = MgvJS.readerContract;
        const goodReader = mgvContracts.reader;
        const book = await goodReader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(5)
        );
        await lc.logOrderBook(book, outbound_tkn, inbound_tkn);
        // const market = await MgvJS.market({ base: outName, quote: inName });
        // const book = market.book();
        // console.log(book);
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
