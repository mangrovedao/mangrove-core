const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");
const { getProvider } = require("scripts/helper.js");

async function main() {
  const provider = getProvider();

  const tester = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    provider
  );

  const baseName = process.env["BASE"];
  const quoteName = process.env["QUOTE"];
  const amount = Number(process.env["AMOUNT"]);
  // sanity check
  if (!baseName || !quoteName || !amount) {
    throw Error(
      "Missing environment variables, must provide BASE, QUOTE, AMOUNT"
    );
  }
  const MgvAPI = await Mangrove.connect({
    signer: tester,
  });

  let MangoRaw = (
    await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
  ).connect(tester);

  let Mango = await MgvAPI.offerLogic(
    MangoRaw.address,
    false
  ).liquidityProvider({ base: baseName, quote: quoteName });
  const tx = await Mango.fundMangrove(amount);
  await tx.wait();
  console.log(
    `Funded`,
    amount,
    `MATICS to (${baseName},${quoteName}) Mango (${Mango.logic.address})`
  );
  console.log(await Mango.balanceOnMangrove());
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
