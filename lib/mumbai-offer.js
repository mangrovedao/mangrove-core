function contractOfToken(hre, provider, tokenName) {
  function tryGet(cfg, name) {
    if (cfg.has(name)) {
      return cfg.get(name);
    }
  }
  const tkCfg = tryGet(hre.env, `tokens.${tokenName}`);
  const tkAddr = tryGet(tkCfg, "address");
  const tkAbi = require(tryGet(tkCfg, "abi"));
  return new ethers.Contract(tkAddr, tkAbi, provider);
}

async function configureOffer() {
  const hre = require("hardhat");
  // config is a module (one can use for instance config.has)
  const networkConfig = require("config");
  if (networkConfig.has("mumbai")) {
    hre.env = networkConfig.get("mumbai");
  } else {
    console.warn("No configuration found for mumbai");
    return;
  }

  // from https://docs.aave.com/developers/deployed-contracts/matic-polygon-market
  const daiAddress = "0x001B3B4d0F3714Ca98ba10F6042DaEbF0B1B7b6F";
  const usdcAddress = "0x2058A9D7613eEE744279e3856Ef0eAda5FCbaA7e";
  const wethAddress = "0x3C68CE8504087f89c640D02d133646d98e64ddd9";

  const url = hre.network.config.url;
  const provider = new hre.ethers.providers.JsonRpcProvider(url);
  // Privileged account is 0 by convention
  const deployer = (await hre.getUnnamedAccounts())[0];
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

  //// Connecting to mangrove via Mangrove.js
  // const { Mangrove } = require("../../mangrove.js");
  // const mgv = await Mangrove.connect(url);
  const mgv = await hre.ethers.getContract("Mangrove");
  const mgov = await mgv.governance();
  if (mgov != deployer) {
    console.error(
      "Deployer is not the admin of the deployed mangrove contract"
    );
    return;
  }

  const weth = contractOfToken(hre, provider, "wEth");
  const dai = contractOfToken(hre, provider, "dai");
  const usdc = contractOfToken(hre, provider, "usdc");

  let overrides = { value: ethers.utils.parseEther("1.0") };
  await mgv["fund(address)"](MumbaiMinter.address, overrides);
  const tokenPrices = [
    // in MATICS
    [weth, ethers.utils.parseEther("2700")], // 1 eth = 2700 Matic
    [dai, ethers.utils.parseEther("0.58")], // 1 usd = 0.58 Matic
    [usdc, ethers.utils.parseEther("0.58")],
  ];
  const gasreq = ethers.BigNumber.from(30000);
  const gasprice = ethers.BigNumber.from(0);
  const pivot = ethers.BigNumber.from(0);

  const mgv_gasprice = ethers.utils.parseUnits("60", 9); // 30 Gwei
  const MgvReader = await hre.ethers.getContract("MgvReader");

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

        makerWants = ethers.utils
          .parseUnits("1000", inDecimals)
          .mul(ethers.utils.parseEther("0.58"))
          .div(inTknInMatic); // makerWants
        makerGives = ethers.utils
          .parseUnits("1000", outDecimals)
          .mul(ethers.utils.parseEther("0.58"))
          .div(outTknInMatic); // makerGives

        //const density_outIn = ;
        await mgv.connect(signer).activate(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(30), //fee 0.3%
          ethers.BigNumber.from(10000), // density should be computed using gives and gasprice.
          ethers.BigNumber.from(20000), // overhead gas
          ethers.BigNumber.from(20000) // offer gas
        );
        const ofrTx = await MumbaiMinter.newOffer(
          outbound_tkn.address, //e.g weth
          inbound_tkn.address, //e.g dai
          makerWants,
          makerGives,
          gasreq,
          gasprice,
          pivot
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
exports.configureOffer = configureOffer;
