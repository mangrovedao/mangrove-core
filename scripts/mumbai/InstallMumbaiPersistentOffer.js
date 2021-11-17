const hre = require("hardhat");
const networkConfig = require("config");
//const activatePair = require("governance/activateOfferList");

async function main() {
  //const hre = require("hardhat");

  function contractOfToken(env, provider, tokenName) {
    function tryGet(cfg, name) {
      if (cfg.has(name)) {
        return cfg.get(name);
      }
    }
    const tkCfg = tryGet(env, `tokens.${tokenName}`);
    const tkAddr = tryGet(tkCfg, "address");
    const tkAbi = require(tryGet(tkCfg, "abi"));
    return new ethers.Contract(tkAddr, tkAbi, provider);
  }

  const url = hre.network.config.url;
  const provider = new hre.ethers.providers.JsonRpcProvider(url);
  //console.log(await provider.listAccounts());

  let env = {};
  if (networkConfig.has("network")) {
    env = networkConfig.get("network");
  } else {
    console.warn("No configuration found for current network");
    return;
  }

  // Privileged account is 0 by convention
  const deployer = (await provider.listAccounts())[0];
  //  const deployer = (await hre.getUnnamedAccounts())[0]; from some reason this does not work
  const signer = await provider.getSigner(deployer);

  // accessing ethers.js MumbaiMinter
  const MumbaiMinter = await hre.ethers.getContract("MumbaiMinter");
  const minterAdmin = await MumbaiMinter.admin();
  if (minterAdmin != deployer) {
    console.error(
      "Deployer is not the admin of the deployed persistent offer contract"
    );
    return;
  }

  const mgv = await hre.ethers.getContract("Mangrove");

  const weth = contractOfToken(env, provider, "wEth");
  const dai = contractOfToken(env, provider, "dai");
  const usdc = contractOfToken(env, provider, "usdc");

  let overrides = { value: ethers.utils.parseEther("1.0") };
  await mgv["fund(address)"](MumbaiMinter.address, overrides);
  const tokenPrices = [
    // in MATICS
    [weth, ethers.utils.parseEther("2700")], // 1 eth = 2700 Matic
    [dai, ethers.utils.parseEther("0.58")], // 1 usd = 0.58 Matic
    [usdc, ethers.utils.parseEther("0.58")],
  ];
  const ofr_gasreq = ethers.BigNumber.from(30000);
  const ofr_gasprice = ethers.BigNumber.from(0);
  const ofr_pivot = ethers.BigNumber.from(0);

  const MgvReader = await hre.ethers.getContract("MgvReader");
  const [global] = await MgvReader.config(
    ethers.constants.AddressZero,
    ethers.constants.AddressZero
  );
  const mgv_gasprice = global.gasprice;

  let inName;
  let inDecimals;
  let outName;
  let outDecimals;
  let makerWants;
  let makerGives;

  for (let [outbound_tkn, outTknInMatic] of tokenPrices) {
    const tx = await MumbaiMinter.approveMangrove(
      outbound_tkn.address,
      ethers.constants.MaxUint256
    );
    await tx.wait();

    outName = await outbound_tkn.name();
    outDecimals = await outbound_tkn.decimals();

    for (let [inbound_tkn, inTknInMatic] of tokenPrices) {
      if (outbound_tkn.address != inbound_tkn.address) {
        inName = await inbound_tkn.name();
        inDecimals = await inbound_tkn.decimals();

        const overhead = await eval_overhead([outbound_tkn, inbound_tkn]);

        makerWants = ethers.utils
          .parseUnits("1000", inDecimals)
          .mul(ethers.utils.parseEther("0.58"))
          .div(inTknInMatic); // makerWants
        makerGives = ethers.utils
          .parseUnits("1000", outDecimals)
          .mul(ethers.utils.parseEther("0.58"))
          .div(outTknInMatic); // makerGives

        const density_outIn = mgv_gasprice
          .mul(ethers.utils.parseUnits("10", outDecimals))
          .div(outTknInMatic);

        await mgv.connect(signer).activate(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(30), //fee 0.3%
          density_outIn,
          ethers.BigNumber.from(20000), // overhead gas
          overhead // offer gas
        );
        const ofrTx = await MumbaiMinter.newOffer(
          outbound_tkn.address, //e.g weth
          inbound_tkn.address, //e.g dai
          makerWants,
          makerGives,
          ofr_gasreq,
          ofr_gasprice,
          ofr_pivot
        );
        await ofrTx.wait();
        const [, ids, offers, details] = await MgvReader.offerList(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(0),
          ethers.BigNumber.from(1)
        );
        console.log(
          `Out[${outName}]`,
          `Inb[${inName}]`,
          ethers.utils.formatUnits(offers[0].wants, inDecimals),
          ethers.utils.formatUnits(offers[0].gives, outDecimals)
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
