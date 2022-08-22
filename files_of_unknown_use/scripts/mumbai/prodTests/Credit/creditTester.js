const { ethers } = require("hardhat");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  const provider = ethers.getDefaultProvider(network.config.url);

  const tester = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    provider
  );

  if (!process.env["TOKEN"]) {
    throw Error("Missing TOKEN environment variable");
  }
  if (!process.env["AMOUNT"]) {
    throw Error("Missing AMOUNT environment variable");
  }

  let mgv = await Mangrove.connect({ signer: tester });
  let token = mgv.token(process.env["TOKEN"]);
  let amount = Number(process.env["AMOUNT"]);

  console.log(
    `Trying to mint ${amount} (${token.toUnits(
      amount
    )} raw units) tokens from ${process.env["TOKEN"]} (${
      token.contract.address
    })`
  );
  let tx = await token.contract.mint(token.toUnits(amount));
  console.log("Processing...");
  await tx.wait();
  console.log("Success!");
  if (process.env["TO"]) {
    console.log(`Transfering freshly minted tokens to ${process.env["TO"]}`);
    tx = await token.transfer(process.env["TO"], amount);
    await tx.wait();
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
