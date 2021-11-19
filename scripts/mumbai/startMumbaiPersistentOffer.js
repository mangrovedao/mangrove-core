const hre = require("hardhat");
const helper = require("../helper");

async function main() {
  const MumbaiMinter = await hre.ethers.getContract("MumbaiMinter");
  const mgv = await helper.getMangrove();
  const signerAddr = await MumbaiMinter.signer.getAddress();
  const admin = await MumbaiMinter["admin()"]();

  const wethAddr = helper.contractOfToken("wEth").address;
  const daiAddr = helper.contractOfToken("dai").address;
  const usdcAddr = helper.contractOfToken("usdc").address;

  let overrides = { value: ethers.utils.parseEther("1.0") };
  await mgv.contract["fund(address)"](MumbaiMinter.address, overrides);

  // reading deploy oracle for the deployed network
  const oracle = require(`../${hre.network.name}/activationOracle`);

  const tokenParams = [
    [wethAddr, "WETH", 18, ethers.utils.parseEther(oracle["WETH"].price)],
    [daiAddr, "DAI", 18, ethers.utils.parseEther(oracle["DAI"].price)],
    [usdcAddr, "USDC", 6, ethers.utils.parseEther(oracle["USDC"].price)],
  ];

  const ofr_gasreq = ethers.BigNumber.from(500000);
  const ofr_gasprice = ethers.BigNumber.from(0);
  const ofr_pivot = ethers.BigNumber.from(0);

  const usdToNative = ethers.utils.parseEther(oracle["USDC"].price);

  for (const [
    outbound_tkn,
    outName,
    outDecimals,
    outTknInMatic,
  ] of tokenParams) {
    const tx = await MumbaiMinter.approveMangrove(
      outbound_tkn,
      ethers.constants.MaxUint256
    );
    await tx.wait();

    for (const [inbound_tkn, inName, inDecimals, inTknInMatic] of tokenParams) {
      if (outbound_tkn != inbound_tkn) {
        const makerWants = ethers.utils
          .parseUnits("1000", inDecimals)
          .mul(usdToNative)
          .div(inTknInMatic); // makerWants
        const makerGives = ethers.utils
          .parseUnits("1000", outDecimals)
          .mul(usdToNative)
          .div(outTknInMatic); // makerGives

        const ofrTx = await MumbaiMinter.newOffer(
          outbound_tkn, //e.g weth
          inbound_tkn, //e.g dai
          makerWants,
          makerGives,
          ofr_gasreq,
          ofr_gasprice,
          ofr_pivot
        );
        await ofrTx.wait();
        const [, , offers] = await mgv.reader.offerList(
          outbound_tkn,
          inbound_tkn,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(1)
        );
        console.log(
          `Out[${outName}]`,
          `Inb[${inName}]`,
          ethers.utils.formatUnits(offers[0].wants, inDecimals),
          ethers.utils.formatUnits(offers[0].gives, outDecimals)
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
