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

  const rawLogic = (await hre.ethers.getContract("OfferProxy")).connect(wallet);

  // just manually getting the address of OfferProxy would suffice here
  const logic = MgvAPI.offerLogic(rawLogic.address);

  for (const tokenName of ["WETH", "USDC", "DAI"]) {
    console.log(`* Approving Lender for minting ${tokenName}`);
    const txLender = await rawLogic.approveLender(
      MgvAPI.token(tokenName).address,
      hre.ethers.constants.MaxUint256
    );
    await txLender.wait();
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
