const hre = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(hre.network.config.url);

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
  const overrides = { gasPrice: ethers.utils.parseUnits("30", "gwei") };

  const rawLogic = (await hre.ethers.getContract("OfferProxy")).connect(wallet);

  // just manually getting the address of OfferProxy would suffice here
  const logic = MgvAPI.offerLogic(rawLogic.address);

  const tx = await logic.activate(["WETH", "USDC", "DAI"], overrides);
  await tx.wait();

  // for (const tokenName of ["WETH", "USDC", "DAI"]) {
  //   console.log(`* Approving Lender for minting ${tokenName}`);
  //   // this approves router of offerProxy for minting overlying (redeem)
  //   const txLender = await rawLogic.approveLender(
  //     MgvAPI.token(tokenName).address,
  //     overrides
  //   );
  //   await txLender.wait();

  //   const mgvApproval = await logic.mangroveAllowance(tokenName);
  //   if (mgvApproval.eq(0)) {
  //     const tx = await logic.approveMangrove(tokenName, overrides);
  //     console.log(
  //       `* OfferProxy contract (${logic.address}) approved Mangrove (${MgvAPI.contract.address}) for ${tokenName} transfer`
  //     );
  //     await tx.wait();
  //   } else {
  //     console.log(
  //       `* OfferProxy already approved Mangrove for ${tokenName} transfer`
  //     );
  //   }
  //   const routerApproval = await logic.routerAllowance(tokenName);
  //   if (routerApproval.eq(0)) {
  //     const tx = await logic.approveRouter(tokenName, overrides);
  //     console.log(
  //       `* OfferProxy contract (${logic.address}) approved router (${
  //         (await logic.router()).address
  //       }) for ${tokenName} transfer`
  //     );
  //     await tx.wait();
  //   }
  // }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
