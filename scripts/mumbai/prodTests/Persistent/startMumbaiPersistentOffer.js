const hre = require("hardhat");
const helper = require("../../../helper");
const lc = require("../../../../lib/libcommon");
const { Mangrove } = require("../../../../../mangrove.js");

async function main() {
  if (!process.env["MUMBAI_TESTER_PRIVATE_KEY"]) {
    console.error("No tester account defined");
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_TESTER_PRIVATE_KEY"],
    helper.getProvider()
  );

  const repostLogic = await hre.ethers.getContract("Reposting");

  const MgvAPI = await Mangrove.connect({
    provider: hre.network.config.url,
    privateKey: wallet.privateKey,
  });

  const weth = MgvAPI.token("WETH");
  const dai = MgvAPI.token("DAI");
  const usdc = MgvAPI.token("USDC");

  MgvAPI._provider.pollingInterval = 250;

  const markets = [
    [weth, 4287, usdc, 1],
    [weth, 4287, dai, 1],
    [dai, 1, usdc, 1],
  ];

  // const ofr_gasreq = ethers.BigNumber.from(200000);
  // const ofr_gasprice = ethers.BigNumber.from(0);
  // const ofr_pivot = ethers.BigNumber.from(0);

  const fundTx = await MgvAPI.fund(repostLogic.address, 1);
  await fundTx.wait();
  const volume = 5000;

  for (const [base, baseInUSD, quote, quoteInUSD] of markets) {
    const mkr = await MgvAPI.MakerConnect({
      address: repostLogic.address,
      base: base.name,
      quote: quote.name,
    });
    const transferTx = await base.contract.transfer(
      repostLogic.address,
      MgvAPI.toUnits(volume / baseInUSD, base.name),
      { gasLimit: 100000 }
    );
    await transferTx.wait();
    const transferTx_ = await quote.contract.transfer(
      repostLogic.address,
      MgvAPI.toUnits(volume / quoteInUSD, quote.name),
      { gasLimit: 100000 }
    );
    await transferTx_.wait();
    console.log(
      `* Transferred ${volume / baseInUSD} ${
        base.name
      } to persistent offer logic`
    );
    // will hang if pivot ID not correctly evaluated
    const { id: ofrId } = await mkr.newAsk({
      wants: (volume + 10) / quoteInUSD,
      gives: volume / baseInUSD,
    });
    const { id: ofrId_ } = await mkr.newBid({
      wants: (volume + 10) / baseInUSD,
      gives: volume / quoteInUSD,
    });
    console.log(
      `* Posting new persistent ask ${ofrId} and bid ${ofrId_} on (${base.name},${quote.name}) Market`
    );
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
