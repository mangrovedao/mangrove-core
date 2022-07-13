// this script assumes dotenv package is installed `(npm install dotenv --save)`
// and you have MUMBAI_NODE_URL and MUMBAI_TESTER_PRIVATE_KEY in your .env file
util.inspect.replDefaults.depth = 0;
const env = require("dotenv").config();
const { Mangrove } = require("../git/mangrove/packages/mangrove.js");
const ethers = require("ethers");

// BUG: needs to override gasPrice for all signed tx
// otherwise ethers.js gives 1.5 gwei which is way too low
const overrides = { gasPrice: ethers.utils.parseUnits("60", "gwei") };

const provider = new ethers.providers.WebSocketProvider(
  env.parsed.MUMBAI_NODE_URL
);

let wallet = new ethers.Wallet(env.parsed.MUMBAI_TESTER_PRIVATE_KEY, provider);

//connecting the API to Mangrove
let mgv = await Mangrove.connect({ signer: wallet });
// BUG: this doesn't work if running a local node forking mumbai
// Uncaught:
// Error: missing response (requestBody="{\"method\":\"net_version\",\"id\":46,\"jsonrpc\":\"2.0\"}", requestMethod="POST", serverError={"errno":-61,"code":"ECONNREFUSED","syscall":"connect","address":"::1","port":8545}, url="http://localhost:8545", code=SERVER_ERROR, version=web/5.6.1)
// at Logger.makeError (/Users/jeankrivine/Documents/sandbox/node_modules/@ethersproject/logger/lib/index.js:233:21)
// at Logger.throwError (/Users/jeankrivine/Documents/sandbox/node_modules/@ethersproject/logger/lib/index.js:242:20)
// at /Users/jeankrivine/Documents/sandbox/node_modules/@ethersproject/web/lib/index.js:252:36
// at step (/Users/jeankrivine/Documents/sandbox/node_modules/@ethersproject/web/lib/index.js:33:23) {
// reason: 'missing response',
// code: 'SERVER_ERROR',
// requestBody: '{"method":"net_version","id":46,"jsonrpc":"2.0"}',
// requestMethod: 'POST',
// serverError: [Error],
// url: 'http://localhost:8545'
// }

//connecting mgv to a market
let market = await mgv.market({ base: "DAI", quote: "USDC" });

// check its live
market.consoleAsks(["id", "price", "volume"]);

/// connecting to offerProxy's onchain logic
const myLogic = mgv.offerLogic("0x8f251D2789c3AE3054C24B4319e357C8AB45697a");
const maker = await myLogic.liquidityProvider(market);

// allowing logic to pull my overlying to finance my offers
tx = await myLogic.approveToken("aDAI", overrides);
await tx.wait();

tx = await myLogic.approveToken("aUSDC", overrides);
await tx.wait();

// checking needed provision
prov = await maker.computeAskProvision();
// BUG: this currenlty returns zero because API is not up to date with Multi Maker way of funding offers

router_address = await maker.logic.router();
aaveMod = myLogic.aaveModule(router_address);
await routerRaw.debtToken(mgv.token("DAI").address);

const { id: ofr_id } = await maker.newAsk({
  wants: 1000,
  gives: 1000,
  fund: ethers.utils.parseEther("0.1"),
  overrides,
});
// BUG: this results in a throw of the API:
// Uncaught { revert: false, exception: 'tx mined but filter never returned true' }

const result = await market.buy({ volume: 1000, price: 1 }, overrides);
