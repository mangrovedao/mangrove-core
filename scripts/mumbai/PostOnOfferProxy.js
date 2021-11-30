const hre = require("hardhat");
const helper = require("../helper");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }
  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );
  const offerProxy = (await hre.ethers.getContract("OfferProxy")).connect(
    wallet
  );
  const aave = helper.getAave();

  for (const [token, name] of [
    [weth, "WETH"],
    [dai, "DAI"],
    [usdc, "USDC"],
  ]) {
    let overrides = { value: lc.parseToken("0.1", 18) };
    mkrTxs[i++] = await offerProxy
      .connect(players.maker.signer)
      .fundMangrove(players.maker.address, overrides);
    let offerId = await lc.newOffer(
      mgv,
      reader,
      makerContract.connect(players.maker.signer),
      "DAI", // outbound
      "WETH", // inbound
      lc.parseToken("0.5", await lc.getDecimals("WETH")), // required WETH
      lc.parseToken("1000.0", await lc.getDecimals("DAI")) // promised DAI
    );
  }
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
