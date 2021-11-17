const hre = require("hardhat");
const helper = require("../helper");
const chalk = require("chalk");

async function main() {
  const env = helper.getCurrentNetworkEnv();
  const provider = helper.getProvider();
  // Privileged account should be 0 by convention
  const deployer = (await provider.listAccounts())[0];
  //  const deployer = (await hre.getUnnamedAccounts())[0]; from some reason this does not work
  const signer = await provider.getSigner(deployer);

  // reading deploy oracle for the deployed network
  const oracle = require(`../${env.network}/deployOracle`);
  //gives price of `tokenSym` in `oracle.native` token
  function priceOf(tokenSym) {
    return oracle[tokenSym].price;
  }
  //gives gas cost of transfer in `oracle.native` token
  function overheadOf(tokenSym) {
    return parseInt(oracle[tokenSym].transferCost, 10);
  }
  function getMangroveIntParam(param) {
    return parseInt(oracle.Mangrove[param]);
  }

  const mgv = await hre.ethers.getContract("Mangrove");
  if ((await mgv.governance()) != deployer) {
    console.error(
      "Deployer is not the admin of the deployed mangrove contract"
    );
    return;
  }

  const wethAddr = helper.addressOfToken(env, "wEth");
  const daiAddr = helper.addressOfToken(env, "dai");
  const usdcAddr = helper.addressOfToken(env, "usdc");

  const tokenParams = [
    [wethAddr, "WETH", 18, ethers.utils.parseEther(priceOf("WETH"))],
    [daiAddr, "DAI", 18, ethers.utils.parseEther(priceOf("DAI"))],
    [usdcAddr, "USDC", 6, ethers.utils.parseEther(priceOf("USDC"))],
  ];

  const MgvReader = await hre.ethers.getContract("MgvReader");
  const [global] = await MgvReader.config(
    ethers.constants.AddressZero,
    ethers.constants.AddressZero
  );
  const mgv_gasprice = global.gasprice.mul(ethers.utils.parseUnits("1", 9)); //GWEI

  for (const [
    outbound_tkn,
    outName,
    outDecimals,
    outTknInMatic,
  ] of tokenParams) {
    for (const [inbound_tkn, inName] of tokenParams) {
      if (outbound_tkn != inbound_tkn) {
        const overhead = ethers.BigNumber.from(
          overheadOf(outName) + overheadOf(inName)
        );

        let density_outIn = mgv_gasprice
          .add(overhead)
          .add(ethers.BigNumber.from(20000))
          .mul(ethers.utils.parseUnits("10", outDecimals)) // N=10
          .div(outTknInMatic);
        if (density_outIn.eq(0)) {
          // if volume imposed by density is lower than ERC20 precision, set it to minimal
          density_outIn = ethers.BigNumber.from(1);
        }

        await mgv.connect(signer).activate(
          outbound_tkn,
          inbound_tkn,
          ethers.BigNumber.from(getMangroveIntParam("defaultFee")),
          density_outIn,
          ethers.BigNumber.from(getMangroveIntParam("orderOverhead")),
          overhead // transfer induced gas overhead
        );
        console.log(
          chalk.blue(`(${outName},${inName})`),
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
