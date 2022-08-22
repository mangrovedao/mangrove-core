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
  const shift = parseInt(process.env["SHIFT"]);
  const amount = Number(process.env["AMOUNT"]);
  // sanity check
  if (!baseName || !quoteName || !shift) {
    throw Error(
      "Missing environment variables, must provide BASE, QUOTE, SHIFT [AMOUNT]"
    );
  }
  let default_amount;
  if (amount) {
    default_amount = amount;
  } else {
    if (shift < 0) {
      default_amount = baseName === "WETH" ? 0.3 : 1000;
    } else {
      default_amount = quoteName === "WETH" ? 0.3 : 1000;
    }
  }
  const MgvAPI = await Mangrove.connect({
    signer: tester,
  });

  let MangoRaw = (
    await hre.ethers.getContract(`Mango_${baseName}_${quoteName}`)
  ).connect(tester);

  MangoRaw = MangoRaw.connect(tester);
  let Mango = await MgvAPI.offerLogic(
    MangoRaw.address,
    false
  ).liquidityProvider({ base: baseName, quote: quoteName });

  const funding = (await Mango.computeAskProvision()) * Math.abs(shift);
  if (funding > 0) {
    console.log(`* funding mangrove for ${funding} native tokens`);
  }
  const fundTx = await Mango.fundMangrove(funding);
  await fundTx.wait();

  const amounts = new Array(Math.abs(shift));
  amounts.fill(
    MgvAPI.toUnits(default_amount, shift < 0 ? baseName : quoteName),
    0
  );
  const tx = await MangoRaw.set_shift(shift, shift < 0, amounts);
  await tx.wait();
  console.log(
    `Mango (${baseName},${quoteName}) shifted of ${Math.abs(
      shift
    )} position(s) ${shift < 0 ? "down" : "up"}`
  );
  console.log(
    `Current price shift is ${(await MangoRaw.get_shift()).toNumber()}`
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
