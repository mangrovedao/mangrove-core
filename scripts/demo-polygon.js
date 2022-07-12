// this script assumes dotenv package is installed `(npm install dotenv --save)`
// and you have MUMBAI_NODE_URL and MUMBAI_TESTER_PRIVATE_KEY in your .env file
util.inspect.replDefaults.depth = 0;
const env = require("dotenv").config();
const { Mangrove } = require("@mangrovedao/mangrove.js");
const ethers = require("ethers");

const provider = new ethers.providers.JsonRpcProvider(
  env.parsed.MUMBAI_NODE_URL
);

let wallet = new ethers.Wallet(env.parsed.MUMBAI_TESTER_PRIVATE_KEY, provider);

//connecting the API to Mangrove
let mgv = await Mangrove.connect({ signer: wallet });

//connecting mgv to a market
let market = await mgv.market({ base: "DAI", quote: "USDC" });

// check its live
market.consoleAsks(["id", "price", "volume"]);
/// with an onchain logic

const myLogic = mgv.offerLogic("0x8f251D2789c3AE3054C24B4319e357C8AB45697a");
const maker = await myLogic.liquidityProvider(market);

// allowing logic to pull my overlying to finance my offers
overrides = { gasPrice: ethers.utils.parseUnits("60", "gwei") };
tx = await myLogic.approveToken("aDAI", overrides);
await tx.wait();

tx = await myLogic.approveToken("aUSDC", overrides);
await tx.wait();

prov = await maker.computeAskProvision();

const { id: ofr_id } = await maker.newAsk({
  wants: 1000,
  gives: 1000,
  fund: ethers.utils.parseEther("0.1"),
});
