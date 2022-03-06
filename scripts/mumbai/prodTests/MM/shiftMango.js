const { ethers, network } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = new ethers.providers.WebSocketProvider(network.config.url);

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
  const amounts = new Array(Math.abs(shift));
  amounts.fill(
    MgvAPI.toUnits(default_amount, shift < 0 ? baseName : quoteName),
    0
  );
  const tx = await MangoRaw.set_shift(shift, shift < 0, amounts);
  await MangoRaw.OFR_GASREQ();
  await tx.wait();
  console.log(
    `Mango (${baseName},${quoteName}) shifted of ${Math.abs(
      shift
    )} position(s) ${shift < 0 ? "down" : "up"}`
  );
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
