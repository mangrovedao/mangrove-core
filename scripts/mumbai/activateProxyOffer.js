const hre = require("hardhat");
const helper = require("../helper");

async function main() {
  const offerProxy = await hre.ethers.getContract("OfferProxy");

  const weth = helper.contractOfToken("wEth").connect(repostLogic.signer);
  const dai = helper.contractOfToken("dai").connect(repostLogic.signer);
  const usdc = helper.contractOfToken("usdc").connect(repostLogic.signer);

  for (token of [weth, dai, usdc]) {
    const tx = await offerProxy.approveMangrove(
      token.address,
      ethers.constants.MaxUint256
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
