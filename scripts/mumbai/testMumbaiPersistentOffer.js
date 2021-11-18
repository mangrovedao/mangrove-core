const hre = require("hardhat");
const helper = require("../helper");
const chalk = require("chalk");

async function main() {
  const provider = hre.ethers.provider;
  const testRunner = (await hre.getUnnamedAccounts())[1];
  const testSigner = provider.getSigner(testRunner);
  const mgvContracts = await helper.getMangrove();
  const mgv = mgvContracts.contract.connect(testSigner);
  const minter = await hre.ethers.getContract("MumbaiMinter");

  //const mgvReader = mgvContracts.reader.connect(testSigner);

  const weth = helper.contractOfToken("wEth").connect(testSigner);
  const usdc = helper.contractOfToken("usdc").connect(testSigner);

  const filter_trade = mgv.filters.OfferSuccess();
  mgv.on(
    filter_trade,
    (out_tkn, in_tkn, offerId, taker_id, takerWants, takerGives, event) => {
      let outName = "USDC";
      let outDecimals = 6;
      let inName = "WETH";
      let inDecimals = 18;
      if (out_tkn == weth.address) {
        outName = "WETH";
        outDecimals = 18;
        inName = "USDC";
        inDecimals = 6;
      }
      console.log(
        chalk.green("Trade success"),
        `Taker gave ${ethers.utils.formatUnits(
          takerGives,
          inDecimals
        )} ${inName} and received ${ethers.utils.formatUnits(
          takerWants,
          outDecimals
        )} ${outName}`
      );
    }
  );
  const filter_fail = mgv.filters.OfferFail();
  mgv.on(
    filter_fail,
    (
      out_tkn,
      in_tkn,
      offerId,
      taker_id,
      takerWants,
      takerGives,
      data,
      event
    ) => {
      let outName = "USDC";
      let outDecimals = 6;
      let inName = "WETH";
      let inDecimals = 18;
      if (out_tkn == weth.address) {
        outName = "WETH";
        outDecimals = 18;
        inName = "USDC";
        inDecimals = 6;
      }
      console.log(
        chalk.red("Trade Failed"),
        `Taker wanted ${ethers.utils.formatUnits(
          takerGives,
          inDecimals
        )} ${inName} and gave ${ethers.utils.formatUnits(
          takerWants,
          outDecimals
        )} ${outName}`
      );
    }
  );
  const posthook_fail = minter.filters.PosthookFail();
  minter.on(
    posthook_fail,
    (outbound_tkn, inbound_tkn, offerId, message, event) => {
      console.log(chalk.red("Posthook Failed:"), message);
    }
  );

  await weth.mint(ethers.utils.parseEther("10"));
  await usdc.mint(ethers.utils.parseUnits("10000"));

  const wethAmount = ethers.utils.parseEther("0.2");
  const usdcAmount = ethers.utils.parseUnits("1000", 6);

  await weth.approve(mgv.address, ethers.constants.MaxUint256);
  await usdc.approve(mgv.address, ethers.constants.MaxUint256);

  const balWethBefore = await weth.balanceOf(testRunner);
  const balUsdcBefore = await usdc.balanceOf(testRunner);

  await mgv.marketOrder(
    weth.address,
    usdc.address,
    wethAmount,
    usdcAmount,
    true
  );
  await mgv.marketOrder(
    usdc.address,
    weth.address,
    usdcAmount,
    wethAmount,
    true
  );

  const balWethAfter = await weth.balanceOf(testRunner);
  const balUsdcAfter = await usdc.balanceOf(testRunner);

  console.log(
    `Received ${ethers.utils.formatUnits(
      balWethAfter.sub(balWethBefore),
      18
    )} WETH and ${ethers.utils.formatUnits(
      balUsdcAfter.sub(balUsdcBefore),
      6
    )} USDC`
  );
  await helper.sleep(3000);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
