const hre = require("hardhat");
const helper = require("../helper");

async function main() {
  const offerProxy = await hre.ethers.getContract("OfferProxy");

  const weth = helper.contractOfToken("wEth").connect(offerProxy.signer);
  const dai = helper.contractOfToken("dai").connect(offerProxy.signer);
  const usdc = helper.contractOfToken("usdc").connect(offerProxy.signer);

  for (const [token, name] of [
    [weth, "WETH"],
    [dai, "DAI"],
    [usdc, "USDC"],
  ]) {
    const tx = await offerProxy.approveMangrove(
      token.address,
      ethers.constants.MaxUint256
    );
    console.log(
      `OfferProxy contract (${offerProxy.address}) approved Mangrove for ${name} transfer`
    );
    await tx.wait();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
