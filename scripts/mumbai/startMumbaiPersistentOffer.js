const hre = require("hardhat");
const helper = require("../helper");
const lc = require("../../lib/libcommon");

async function main() {
  const repostLogic = await hre.ethers.getContract("Reposting");
  const mgvContracts = await helper.getMangrove();
  const mgv = mgvContracts.contract.connect(repostLogic.signer);

  const weth = helper.contractOfToken("wEth").connect(repostLogic.signer);
  const dai = helper.contractOfToken("dai").connect(repostLogic.signer);
  const usdc = helper.contractOfToken("usdc").connect(repostLogic.signer);

  const tokenParams = [
    [weth, "WETH", 18, ethers.utils.parseEther("1")],
    [dai, "DAI", 18, ethers.utils.parseEther("0.0003")],
    [usdc, "USDC", 6, ethers.utils.parseEther("0.0003")],
  ];

  const ofr_gasreq = ethers.BigNumber.from(100000);
  const ofr_gasprice = ethers.BigNumber.from(0);
  const ofr_pivot = ethers.BigNumber.from(0);

  const usdToNative = ethers.utils.parseEther("0.0003");

  let overrides = { value: ethers.utils.parseEther("1.0") };
  await mgv["fund(address)"](repostLogic.address, overrides);

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

        const ofrTx = await repostLogic.newOffer(
          outbound_tkn.address, //e.g weth
          inbound_tkn.address, //e.g dai
          makerWants,
          makerGives,
          ofr_gasreq,
          ofr_gasprice,
          ofr_pivot
        );
        await ofrTx.wait();
        const book = await mgvContracts.reader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(1)
        );
        lc.logOrderBook(book, outbound_tkn, inbound_tkn);
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
