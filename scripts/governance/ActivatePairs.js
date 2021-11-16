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

  async function eval_overhead(tokens) {
    const recipient = await signer.getAddress();
    let overhead = ethers.BigNumber.from(0);
    for (const i in tokens) {
      const amount = ethers.utils.parseEther("1");
      const tx = await tokens[i].connect(signer).transfer(recipient, amount);
      const ticket = await tx.wait();
      overhead = overhead.add(ticket.gasUsed);
    }
    return overhead;
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

  const mgv = await hre.ethers.getContract("Mangrove");
  const mgov = await mgv.governance();
  if (mgov != deployer) {
    console.error(
      "Deployer is not the admin of the deployed mangrove contract"
    );
    return;
  }

  const weth = contractOfToken(env, provider, "wEth");
  const dai = contractOfToken(env, provider, "dai");
  const usdc = contractOfToken(env, provider, "usdc");

  const tokenPrices = [
    // in MATICS --TODO read price from an external source that should be network specific
    // this is just for Mumbai
    [weth, ethers.utils.parseEther("2700")], // 1 eth = 2700 Matic
    [dai, ethers.utils.parseEther("0.58")], // 1 usd = 0.58 Matic
    [usdc, ethers.utils.parseEther("0.58")],
  ];

  const MgvReader = await hre.ethers.getContract("MgvReader");
  const [global] = await MgvReader.config(
    ethers.constants.AddressZero,
    ethers.constants.AddressZero
  );
  const mgv_gasprice = global.gasprice.mul(ethers.utils.parseUnits("1", 9)); //GWEI

  let inName;
  let inDecimals;
  let outName;
  let outDecimals;

  for (let [outbound_tkn, outTknInMatic] of tokenPrices) {
    outName = await outbound_tkn.name();
    outDecimals = await outbound_tkn.decimals();

    for (let [inbound_tkn, inTknInMatic] of tokenPrices) {
      if (outbound_tkn.address != inbound_tkn.address) {
        inName = await inbound_tkn.name();
        inDecimals = await inbound_tkn.decimals();

        const overhead = await eval_overhead([outbound_tkn, inbound_tkn]);

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
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(30), //fee 0.3%
          density_outIn,
          ethers.BigNumber.from(20000), // overhead gas to execute taker order
          overhead // offer gas
        );
        console.log(
          `(${outName},${inName}) OfferList activated with a required density of ${ethers.utils.formatUnits(
            density_outIn,
            outDecimals
          )} ${outName} per gas units`
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
