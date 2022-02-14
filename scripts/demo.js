// this script assumes dotenv package is installed `(npm install dotenv --save)`
// and you have MUMBAI_NODE_URL and MUMBAI_TESTER_PRIVATE_KEY in your .env file
util.inspect.replDefaults.depth = 0;
const env = require("dotenv").config();
const { Mangrove } = require("@mangrovedao/mangrove.js");
const ethers = require("ethers");
let provider = new ethers.providers.WebSocketProvider(
  env.parsed.MUMBAI_NODE_URL
);

let wallet = new ethers.Wallet(env.parsed.MUMBAI_TESTER_PRIVATE_KEY, provider);

//connecting the API to Mangrove
let mgv = await Mangrove.connect({ signer: wallet });

//connecting mgv to a market
let market = await mgv.market({ base: "DAI", quote: "USDC" });

// check its live
market.consoleAsks();
market.consoleBids();

// create a simple LP on `market`
let directLP = await mgv.liquidityProvider(market);
//
// //Ask on market (promise base (DAI) in exchange of quote (USDC))
// //LP needs to approve Mangrove for base transfer
let tx = await directLP.approveMangroveForBase();
await tx.wait();
await market.base.allowance();
//
// // querying mangrove to know the bounty for posting a new Ask on `market`
let prov = await directLP.computeAskProvision();
tx = await directLP.fundMangrove(prov);
await tx.wait();
//
// //Posting a new Ask
const { id: ofrId } = await directLP.newAsk({ wants: 105, gives: 104 });

/// with an onchain logic

const logic = mgv.offerLogic("0xca02FF4541f9B7B9878e925d7daE87d8A7501C68");
const onchainLP = await logic.liquidityProvider(market);

// approves amBase transfer to logic
const amDAI = mgv.token("amDAI");
tx = await amDAI.approve(logic.address);
await tx.wait();

prov = await onchainLP.computeAskProvision();
tx = await onchainLP.fundMangrove(prov);
await tx.wait();

const { id: ofrId_ } = await onchainLP.newAsk({ wants: 1005, gives: 1004 });
