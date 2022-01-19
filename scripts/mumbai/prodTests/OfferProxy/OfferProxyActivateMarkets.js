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

  // just manually getting the address of OfferProxy would suffice here
  const logic = MgvAPI.offerLogic(
    (await hre.ethers.getContract("OfferProxy")).address
  );

  for (const tokenName of ["WETH", "USDC", "DAI"]) {
    const approval = await logic.mangroveAllowance(tokenName);
    if (approval.eq(0)) {
      const tx = await logic.approveMangrove(tokenName);
      console.log(
        `* OfferProxy contract (${logic.address}) approved Mangrove (${MgvAPI.contract.address}) for ${tokenName} transfer`
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
