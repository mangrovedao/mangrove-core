const hre = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(
    hre.network.config.url
  );

  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );
  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });
  const offerProxy = (await hre.ethers.getContract("OfferProxy")).connect(
    wallet
  );

  const logic = MgvAPI.offerLogic(offerProxy);

  for (const tokenName of ["WETH", "USDC", "DAI"]) {
    const token = MgvAPI.token(tokenName);
    const approval = await token.allowance({
      owner: logic.address,
      spender: MgvAPI.contract.address,
    });
    if (approval.eq(0)) {
      // this ethers.js call should be done via the API
      const tx = await logic.approveMangrove(tokenName);
      console.log(
        `* OfferProxy contract (${
          offerProxy.address
        }) approved Mangrove (${await offerProxy.MGV()}) for ${tokenName} transfer`
      );
      await tx.wait();
    } else {
      console.log(
        `* OfferProxy already approved Mangrove for ${tokenName} transfer`
      );
    }
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
