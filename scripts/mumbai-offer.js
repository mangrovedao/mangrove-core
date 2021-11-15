const hre = require("hardhat");
//const helpers = require("../util/helpers");
// const { BigNumber } = require("@ethersproject/bignumber");

const main = async () => {
  const url = hre.network.config.url;
  const provider = new hre.ethers.providers.JsonRpcProvider(url);
  // const signer = provider.getSigner();
  // const deployer = await signer.getAddress();
  // console.log();

  const deployer = (await hre.getNamedAccounts()).deployer;
  const signer = await provider.getSigner(deployer);
  const MumbaiMinter = await hre.ethers.getContract("MumbaiMinter");
  console.log();
  const minterAdmin = await MumbaiMinter.admin();

  //// Connecting to mangrove via Mangrove.js
  // const { Mangrove } = require("../../mangrove.js");
  // const mgv = await Mangrove.connect(url);
  const mgv = await hre.ethers.getContract("Mangrove");
  const mgov = await mgv.governance();

  const weth = await hre.ethers.getContract("WETH");
  const dai = await hre.ethers.getContract("DAI");
  const usdc = await hre.ethers.getContract("USDC");

  let overrides = { value: ethers.utils.parseEther("1.0") };
  await mgv["fund(address)"](MumbaiMinter.address, overrides);
  const tokenPrices = [
    // in MATICS
    [weth, ethers.utils.parseEther("2700")], // 1 eth = 2700 Matic
    [dai, ethers.utils.parseEther("1.72")], // 1 usd = 1.72 Matic
    [usdc, ethers.utils.parseUnits("1.72", 6)],
  ];
  const gasreq = ethers.BigNumber.from(30000);
  const gasprice = ethers.BigNumber.from(0);
  const pivot = ethers.BigNumber.from(0);

  const mgv_gasprice = ethers.utils.parseUnits("60", 9); // 30 Gwei

  for (let [outbound_tkn, gives] of tokenPrices) {
    await MumbaiMinter.approveMangrove(
      outbound_tkn.address,
      ethers.constants.MaxUint256
    );
    for (let [inbound_tkn, wants] of tokenPrices) {
      if (outbound_tkn.address != inbound_tkn.address) {
        await mgv.connect(signer).activate(
          outbound_tkn.address,
          inbound_tkn.address,
          ethers.BigNumber.from(30), //fee 0.3%
          mgv_gasprice.mul(gives), // density
          ethers.BigNumber.from(20000), // overhead gas
          ethers.BigNumber.from(20000) // offer gas
        );
        console.log();
        await MumbaiMinter.newOffer(
          outbound_tkn.address,
          inbound_tkn.address,
          gives,
          wants,
          gasreq,
          gasprice,
          pivot
        );
      }
    }
  }

  console.log();

  //   const { Mangrove } = require("../../src");

  //   const deployer = (await hre.ethers.getSigners())[1];

  //   const user = (await hre.ethers.getSigners())[0];

  //   const mgv = await Mangrove.connect({
  //     signerIndex: 1,
  //     provider: `http://localhost:${opts.port}`,
  //   });
  //   const mgvContract = mgv.contract;
  //   // const TokenA = await hre.ethers.getContract("TokenA");
  //   // const TokenB = await hre.ethers.getContract("TokenB");

  //   // Setup Mangrove to use MgvOracle as oracle
  //   const mgvOracle = mgv.oracleContract;
  //   await mgvContract.setMonitor(mgvOracle.address);
  //   await mgvContract.setUseOracle(true);
  //   await mgvContract.setNotify(true);

  //   // ensure that unless instructed otherwise,
  //   // MgvOracle has the same gasprice default as Mangrove default
  //   const mgvConfig = await mgv.config();
  //   await mgvOracle.setGasPrice(mgvConfig.gasprice);

  //   // set allowed mutator on MgvOracle to gasUpdater named account
  //   const gasUpdater = (await hre.getNamedAccounts()).gasUpdater;
  //   await mgvOracle.setMutator(gasUpdater);

  //   const activate = (base, quote) => {
  //     return mgvContract.activate(base, quote, 0, 10, 80000, 20000);
  //   };

  //   const userA = await user.getAddress();
  //   console.log("user", userA);
  //   const deployerA = await deployer.getAddress();
  //   console.log("deployer", deployerA);

  //   const approve = (tkn) => {
  //     tkn.contract.mint(userA, mgv.toUnits(tkn.amount, tkn.name));
  //   };

  //   // await activate(TokenA.address,TokenB.address);
  //   // await activate(TokenB.address,TokenA.address);

  //   const tkns = [
  //     { name: "WETH", amount: 1000 },
  //     { name: "DAI", amount: 10_000 },
  //     { name: "USDC", amount: 10_000 },
  //   ];

  //   for (const t of tkns) t.contract = mgv.token(t.name).contract;

  //   const mgv2 = await Mangrove.connect({
  //     signerIndex: 0,
  //     provider: `http://localhost:${opts.port}`,
  //   });

  //   // contract create2 addresses exported by mangrove-solidity to hardhatAddresses

  //   // const mgvContract = mgv.contract;
  //   const mgvReader = mgv.readerContract;
  //   console.log("mgvReader", mgvReader.address);

  //   const newOffer = async (
  //     tkout,
  //     tkin,
  //     wants,
  //     gives,
  //     gasreq = 100_000,
  //     gasprice = 1
  //   ) => {
  //     try {
  //       await mgv.contract.newOffer(
  //         tkout.address,
  //         tkin.address,
  //         tkin.toUnits(wants),
  //         tkout.toUnits(gives),
  //         gasreq,
  //         gasprice,
  //         0
  //       );
  //     } catch (e) {
  //       console.log(e);
  //       console.warn(
  //         `Posting offer failed - tkout=${tkout}, tkin=${tkin}, wants=${wants}, gives=${gives}, gasreq=${gasreq}, gasprice=${gasprice}`
  //       );
  //     }
  //   };

  //   const retractOffer = async (base, quote, offerId) => {
  //     const estimate = await mgv.contract.estimateGas.retractOffer(
  //       base,
  //       quote,
  //       offerId,
  //       true
  //     );
  //     const newEstimate = Math.round(estimate.toNumber() * 1.3);
  //     const resp = await mgv.contract.retractOffer(base, quote, offerId, true, {
  //       gasLimit: newEstimate,
  //     });
  //     const receipt = await resp.wait();
  //     if (!estimate.eq(receipt.gasUsed)) {
  //       console.log(
  //         "estimate != used:",
  //         estimate.toNumber(),
  //         receipt.gasUsed.toNumber()
  //       );
  //     }
  //     return mgv.contract.retractOffer(base, quote, offerId, true);
  //   };

  //   const between = (a, b) => a + rng() * (b - a);

  //   const WethDai = await mgv.market({ base: "WETH", quote: "DAI" });
  //   const WethUsdc = await mgv.market({ base: "WETH", quote: "USDC" });
  //   const DaiUsdc = await mgv.market({ base: "DAI", quote: "USDC" });

  //   const markets = [WethDai, WethUsdc, DaiUsdc];

  //   console.log("Orderbook filler is now running.");

  //   const pushOffer = async (market, ba /*bids|asks*/) => {
  //     let tkout = "base",
  //       tkin = "quote";
  //     if (ba === "bids") [tkout, tkin] = [tkin, tkout];
  //     const book = await market.book();
  //     const buffer = book[ba].length > 30 ? 5000 : 0;

  //     setTimeout(async () => {
  //       let wants, gives;
  //       if (opts.cross) {
  //         if (tkin === "quote") {
  //           wants = 1 + between(0, 0.5);
  //           gives = 1;
  //           console.log("posting ask, price is ", wants / gives);
  //         } else {
  //           gives = 0.5 + between(0.3, 0.8);
  //           wants = 1;
  //           console.log("posting bid, price is ", gives / wants);
  //         }

  //         console.log();
  //       } else {
  //         wants = 1 + between(0, 3);
  //         gives = wants * between(1.001, 4);
  //       }
  //       console.log(
  //         `new ${market.base.name}/${market.quote.name} offer. price ${
  //           tkin === "quote" ? wants / gives : gives / wants
  //         }. wants:${wants}. gives:${gives}`
  //       );
  //       const cfg = await market.config();
  //       console.log(`asks last`, cfg.asks.last, `bids last`, cfg.bids.last);
  //       await newOffer(market[tkout], market[tkin], wants, gives);
  //       pushOffer(market, ba);
  //     }, between(1000 + buffer, 3000 + buffer));
  //   };

  //   const pullOffer = async (market, ba) => {
  //     let tkout = "base",
  //       tkin = "quote";
  //     if (ba === "bids") [tkin, tkout] = [tkout, tkin];
  //     const book = await market.book();

  //     if (book[ba].length !== 0) {
  //       const pulledIndex = Math.floor(rng() * book[ba].length);
  //       const offer = book[ba][pulledIndex];
  //       console.log(
  //         `retracting on ${market.base.name}/${market.quote.name} ${offer.id}`
  //       );
  //       await retractOffer(market[tkout].address, market[tkin].address, offer.id);
  //     }
  //     setTimeout(() => {
  //       pullOffer(market, ba);
  //     }, between(2000, 4000));
  //   };

  //   for (const market of markets) {
  //     pushOffer(market, "asks");
  //     pushOffer(market, "bids");
  //     pullOffer(market, "asks");
  //     pullOffer(market, "bids");
  //   }
};

main(); //catch((e) => console.error(e));
