const hre = require("hardhat");
const helper = require("../helper");
const chalk = require("chalk");

async function main() {
  // reading deploy oracle for the deployed network
  const oracle = require(`../${hre.network.name}/activationOracle`);
  //gives price of `tokenSym` in `oracle.native` token
  function priceOf(tokenSym) {
    return oracle[tokenSym].price;
  }
  //gives gas cost of transfer in `oracle.native` token
  function transferCostOf(tokenSym) {
    return parseInt(oracle[tokenSym].transferCost, 10);
  }
  function getMangroveIntParam(param) {
    return parseInt(oracle.Mangrove[param], 10);
  }

  const mgv = await helper.getMangrove();

  const wethAddr = helper.contractOfToken("wEth").address;
  const daiAddr = helper.contractOfToken("dai").address;
  const usdcAddr = helper.contractOfToken("usdc").address;

  const tokenParams = [
    [wethAddr, "WETH", 18, ethers.utils.parseEther(priceOf("WETH"))],
    [daiAddr, "DAI", 18, ethers.utils.parseEther(priceOf("DAI"))],
    [usdcAddr, "USDC", 6, ethers.utils.parseEther(priceOf("USDC"))],
  ];

  const oracle_gasprice = getMangroveIntParam("gasprice");

  const gaspriceTx = await mgv.contract.setGasprice(
    ethers.BigNumber.from(oracle_gasprice)
  );
  await gaspriceTx.wait();
  console.log(
    chalk.yellow("*"),
    `Setting mangrove gasprice to ${oracle_gasprice} GWEI`
  );

  const gasmaxTx = await mgv.contract.setGasmax(ethers.BigNumber.from(1500000));
  await gasmaxTx.wait();

  console.log(chalk.yellow("*"), `Setting mangrove gasmax to 1.5M`);

  const mgv_gasprice = ethers.utils.parseUnits("1", 9).mul(oracle_gasprice); //GWEI

  for (const [
    outbound_tkn,
    outName,
    outDecimals,
    outTknInMatic,
  ] of tokenParams) {
    for (const [inbound_tkn, inName] of tokenParams) {
      if (outbound_tkn != inbound_tkn) {
        const overhead_gasbase = ethers.BigNumber.from(transferCostOf(inName));
        const offer_gasbase = ethers.BigNumber.from(
          transferCostOf(inName) + transferCostOf(outName)
        );
        const overheadTx = await mgv.contract.setGasbase(
          outbound_tkn,
          inbound_tkn,
          overhead_gasbase,
          offer_gasbase
        );
        await overheadTx.wait();
        console.log(
          chalk.yellow("*"),
          `Setting (${outName},${inName}) overhead_gasbase to ${transferCostOf(
            inName
          )} gas units`
        );
        console.log(
          chalk.yellow("*"),
          `Setting (${outName},${inName}) offer_gasbase to ${
            transferCostOf(inName) + transferCostOf(outName)
          } gas units`
        );

        let density_outIn = mgv_gasprice
          .add(overhead_gasbase)
          .add(offer_gasbase)
          .mul(
            ethers.utils.parseUnits(oracle.Mangrove.coverFactor, outDecimals)
          ) // N=50
          .div(outTknInMatic);
        if (density_outIn.eq(0)) {
          // if volume imposed by density is lower than ERC20 precision, set it to minimal
          density_outIn = ethers.BigNumber.from(1);
        }

        await mgv.contract.activate(
          outbound_tkn,
          inbound_tkn,
          ethers.BigNumber.from(getMangroveIntParam("defaultFee")),
          density_outIn,
          offer_gasbase,
          overhead_gasbase
        );
        console.log(
          chalk.yellow("*"),
          `(${outName},${inName})`,
          `OfferList activated with a required density of ${ethers.utils.formatUnits(
            density_outIn,
            outDecimals
          )} ${outName} per gas units`,
          `and a fee of ${ethers.utils.formatUnits(
            getMangroveIntParam("defaultFee"),
            3
          )}%`
        );
      }
    }
  }
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
