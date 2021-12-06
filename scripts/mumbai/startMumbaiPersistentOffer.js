const hre = require("hardhat");
const helper = require("../helper");
const lc = require("../../lib/libcommon");

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

  const mgvContracts = await helper.getMangrove();
  const mgv = mgvContracts.contract.connect(wallet);

  const weth = helper.contractOfToken("wEth").connect(wallet);
  const dai = helper.contractOfToken("dai").connect(wallet);
  const usdc = helper.contractOfToken("usdc").connect(wallet);

  const tokenParams = [
    [dai, "DAI", 18, ethers.utils.parseEther("0.0003")],
    [weth, "WETH", 18, ethers.utils.parseEther("1")],
    [usdc, "USDC", 6, ethers.utils.parseEther("0.0003")],
  ];

  const ofr_gasreq = ethers.BigNumber.from(200000);
  const ofr_gasprice = ethers.BigNumber.from(0);
  const ofr_pivot = ethers.BigNumber.from(0);

  const usdToNative = ethers.utils.parseEther("0.0003");

  let overrides = { value: ethers.utils.parseEther("1.0"), gasLimit: 60000 };
  const fundTx = await mgv["fund(address)"](repostLogic.address, overrides);
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
        const makerWants = ethers.utils
          .parseUnits("1000", inDecimals)
          .mul(usdToNative)
          .div(inTknInMatic); // makerWants
        const makerGives = ethers.utils
          .parseUnits("1000", outDecimals)
          .mul(usdToNative)
          .div(outTknInMatic); // makerGives

        const transferTx = await outbound_tkn.transfer(
          repostLogic.address,
          makerGives
        );
        await transferTx.wait();
        console.log(
          `* Transfering ${ethers.utils.formatUnits(
            makerGives,
            outDecimals
          )} ${outName} to persistent offer logic`
        );
        const ofrTx = await repostLogic.newOffer(
          outbound_tkn.address, //e.g weth
          inbound_tkn.address, //e.g dai
          makerWants,
          makerGives,
          ofr_gasreq,
          ofr_gasprice,
          ethers.BigNumber.from(180)
        );
        await ofrTx.wait();
        console.log(
          `* Posting new persistent offer on (${outName},${inName}) offer list`
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
