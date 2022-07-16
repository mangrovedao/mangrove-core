const hre = require("hardhat");
const chalk = require("chalk");
const { Mangrove } = require("../../../mangrove.js");

async function main() {
  const overrides = { gasPrice: ethers.utils.parseUnits("60", "gwei") };

  const provider = ethers.getDefaultProvider(hre.network.config.url);
  if (!process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"]) {
    console.error(
      "No deployer account defined, make sure MUMBAI_DEPLOYER_PRIVATE_KEY is set"
    );
  }

  const wallet = new ethers.Wallet(
    process.env["MUMBAI_DEPLOYER_PRIVATE_KEY"],
    provider
  );

  const MgvAPI = await Mangrove.connect({
    signer: wallet,
  });
  console.log(
    `Will activate a market on Mangrove (${chalk.grey(
      MgvAPI.contract.address
    )})`
  );

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

  async function activateOfferList(outName, outPrice, inName, mgv_gasprice) {
    const outbound_tkn = MgvAPI.token(outName);
    const inbound_tkn = MgvAPI.token(inName);

    const offer_gasbase = ethers.BigNumber.from(
      (transferCostOf(inName) + transferCostOf(outName)) * 2
    );
    const overheadTx = await MgvAPI.contract.setGasbase(
      outbound_tkn.address,
      inbound_tkn.address,
      offer_gasbase,
      overrides
    );
    await overheadTx.wait();

    console.log(
      chalk.yellow("*"),
      `Setting (${outName},${inName}) offer_gasbase to ${
        (transferCostOf(inName) + transferCostOf(outName)) * 2
      } gas units`
    );

    // density (in outbound tokens per gas unit)
    // gives*price_in_ETH / (gasbase + gasreq)*gasprice (in ETH) >= cover_factor > 1

    let density_outIn = mgv_gasprice
      .add(offer_gasbase)
      .mul(
        ethers.utils.parseUnits(
          oracle.Mangrove.coverFactor,
          outbound_tkn.decimals
        )
      ) // N=50
      .div(ethers.utils.parseEther(outPrice));
    if (density_outIn.eq(0)) {
      // if volume imposed by density is lower than ERC20 precision, set it to minimal
      density_outIn = ethers.BigNumber.from(1);
    }

    const txActivate = await MgvAPI.contract.activate(
      outbound_tkn.address,
      inbound_tkn.address,
      ethers.BigNumber.from(getMangroveIntParam("defaultFee")),
      density_outIn,
      offer_gasbase,
      overrides
    );
    await txActivate.wait();
    console.log(
      chalk.yellow("*"),
      `(${outName},${inName})`,
      `OfferList activated with a required density of ${ethers.utils.formatUnits(
        density_outIn,
        outbound_tkn.decimals
      )} ${outName} per gas units`,
      `and a fee of ${ethers.utils.formatUnits(
        getMangroveIntParam("defaultFee"),
        3
      )}%`
    );
  }

  if (!process.env["BASE"] || !process.env["QUOTE"]) {
    throw Error("BASE and QUOTE environment variables should be defined");
  }
  if (!process.env["SET_GAS"]) {
    console.warn(
      "SET_GAS is not positioned. Will not update gas parameters on Mangrove"
    );
  }
  const base = process.env["BASE"];
  const basePrice = priceOf(base);
  const quote = process.env["QUOTE"];
  const quotePrice = priceOf(quote);

  const oracle_gasprice = getMangroveIntParam("gasprice");

  if (process.env["SET_GAS"]) {
    const gaspriceTx = await MgvAPI.contract.setGasprice(
      ethers.BigNumber.from(oracle_gasprice),
      overrides
    );
    await gaspriceTx.wait();
    console.log(
      chalk.yellow("*"),
      `Setting mangrove gasprice to ${oracle_gasprice} GWEI`
    );
    const gasmaxTx = await MgvAPI.contract.setGasmax(
      ethers.BigNumber.from(1500000),
      overrides
    );
    await gasmaxTx.wait();
    console.log(chalk.yellow("*"), `Setting mangrove gasmax to 1.5M`);
  }
  const mgv_gasprice = ethers.utils.parseUnits("1", 9).mul(oracle_gasprice); //GWEI
  let market = await MgvAPI.market({ base: base, quote: quote });

  console.log(`Activating market (${base},${quote}) on Mangrove...`);
  await activateOfferList(base, basePrice, quote, mgv_gasprice);
  await activateOfferList(quote, quotePrice, base, mgv_gasprice);
}
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
