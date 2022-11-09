// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {IERC20} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {LockedWrapperToken} from "mgv_src/usual/LockedWrapperToken.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {PLUsMgvStrat} from "mgv_src/usual/PLUsMgvStrat.sol";
import {Deployer} from "mgv_script/lib/Deployer.sol";

// FIXME/TODO:
// - make a demo clone with no real secrets
// - implement trivial price-lock contract
//   - no checks, just wrap LUsDAO in PLUsDAO and post offer
//
// - market
//   - for demo, we can accept that there is a bids list, we just wont use it
//   - can't we use symbols instead of addresses in the activation script?
//
// - mangrove.js
//   - how do we get localhost addresses into mangrove.js?
//   - how do we get ABI's into mangrove.js?
//
// - web app
//   - what is needed to add support for UsUSD and Meta-PLUsDAO tokens?
//   - will the web app blow up when there are no bids? (not a problem for this demo)
// 
// - approvals/whitelisting
//   + PLUsDAO needed approvals/whitelisting:
//     + LUsDAO:
//       + whitelisted to allow taking/releasing custody of LUsDAO tokens  <-- achieved in deployment script
//       + approved to allow transfers from: seller                        <-- achieved in mangrove.js
//   - Meta-PLUsDAO needed approvals/whitelisting:
//     - PLUsDAO:
//       + whitelisted to allow transfers and unlocks                      <-- achieved in deployment script
//       - approved to allow transfers from:
//         + PLUsMgvStrat                                                  <-- achieved in PLUsMgvStrat constructor
//         - Mangrove                                                      <-- FIXME I don't see a way to get Mangrove to approve these transfers... Maybe the meta-token should take custody instead, then this isn't needed
//   + Price-Locking dApp approvals/whitelisting:                          <-- N/A in this demo
//     + PLUsDAO:
//       + whitelisted to allow locking
//     + PLUsMgvStrat:
//       + whitelisted to allow posting offers
//   + PLUsMgvStrat needed approvals/whitelisting:
//     + PLUsDAO:
//       + whitelisted to allow transfers/locking                          <-- achieved in deployment script
//       + approved to allow transfers from: seller                        <-- N/A in this demo
//     + Meta-PLUsDAO:
//       + approved to allow transfers from: seller                        <-- achieved in mangrove.js via LiquidityProvider
//   + Mangrove needed approvals/whitelisting:
//     + UsUSD:
//       + approved to allow transfers from: proxy/taker                   <-- achieved in mangrove.js
//     + Meta-PLUsDAO:
//       + approved to allow transfers from: PLUsMgvStrat                  <-- achieved in deployment script via activation
//       

// DONE:
// - implement LUsDAO, PLUsDAO, Meta-PLUsDAO
// - consider whether TakerProxy is required
//   - for a demo, it shouldn't be needed and it makes mangrove.js less useful

// DEMO INSTRUCTIONS
// Create the following terminal:
//    Terminal 1 - local chain
//    Terminal 2 - deploy and configure contracts
//    Terminal 3 - seller using mangrove.js
//    Terminal 4 - taker using mangrove.js
//
// The contract terminals are in mangrove-core on the demo/usual branch
// The mangrove.js terminal is in mangrove-ts/packages/mangrove.js on the demo/usual branch
// All contracts are deployed and owned by LOCALHOST_DEPLOYER_PRIVATE_KEY

/* Terminal 1 - local chain
source .env
anvil --port 8545 --mnemonic $LOCALHOST_MNEMONIC --silent
*/

/* Terminal 2 - deploy & configure contracts
source .env

# Deploy Mangrove and periphery contracts
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast MangroveDeployer

# Deploy Usual contracts and mint tokens
SELLER_ADDRESS=$LOCALHOST_SELLER_ADDRESS \
TAKER_ADDRESS=$LOCALHOST_TAKER_ADDRESS \
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast UsualDemoDeployer

# Configure Meta-PLUsDAO/UsDAO market
# NB: Standard ActivateMarket doesn't work for meta-tokens, so we'll use a temp meta-token alternative instead
TKN1=Meta-PLUsDAO \
TKN2=UsUSD \
TKN1_IN_GWEI=$(cast ff 9 1) TKN2_IN_GWEI=$(cast ff 9 1) \
FEE=0 forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  ActivateMarketMetaToken
*/

/* Terminal 3 - seller using mangrove.js
source .env
node

// Limit the output to the given depth when printing results.
// We typically set this to 0 or 1.
//
// If you don't set this, the REPL will print A LOT of information after each command.
//
// It's typically better to assign results to a variable and then selectively
// print the parts of the result object that are relevant.
util.inspect.replDefaults.depth = 0;

// Load the .env file into process.env
// Any environment variables that were already set are not overriden.
var parsed = require("dotenv").config();

// Load the mangrove.js API
const { Mangrove, MgvToken, ethers } = require("@mangrovedao/mangrove.js");

// Connect to the chosen node provider
const provider = new ethers.providers.WebSocketProvider(
  // Change this to the appropriate env var for the chain you want to connect to
  process.env.LOCALHOST_URL
);

// Set up a wallet that will be used to sign tx's in the demo
let seller = new ethers.Wallet(process.env.LOCALHOST_SELLER_PRIVATE_KEY, provider);

// Connect to Mangrove
let mgv = await Mangrove.connect({ signer: seller });

// Connect to tokens
let UsUSD = mgv.token("UsUSD");
let UsDAO = mgv.token("UsDAO");
let LUsDAO = mgv.token("LUsDAO");
let PLUsDAO = mgv.token("PLUsDAO");
let MetaPLUsDAO = mgv.token("Meta-PLUsDAO");

// Util for printing relevant balances
async function printBalances(address) {
  console.group("Balances for " + address);
  for (var t of [UsUSD, UsDAO, LUsDAO, PLUsDAO, MetaPLUsDAO]) {
    let balance = await t.balanceOf(address);
    console.log(`${t.name}:\t\t${balance}`);
  }
  console.groupEnd();
}

await printBalances(seller.address);

// Connect to the market
let market = await mgv.market({base: 'Meta-PLUsDAO', quote:'UsUSD'});
market.consoleAsks();

// Connect to PLUsMgvStrat
let plusMgvStrat = mgv.offerLogic('0x610178dA211FEF7D417bC0e6FeD39F05609AD788');
// Use liquidity provider, ie. the PLUsMgvStrat connected to a market
let liquidityProvider = await plusMgvStrat.liquidityProvider(market);

// Approve PLUsMgvStrat to transfer Meta-PLUsDAO tokens on seller's behalf
let tx = await liquidityProvider.approveAsks(); 0;
let txReceipt = await tx.wait(); 0;
// Approve Meta-PLUsDAO to transfer PLUsDAO tokens on seller's behalf
tx = await PLUsDAO.approve(MetaPLUsDAO.address); 0;
txReceipt = await tx.wait(); 0;
// Approve PLUsDAO to transfer LUsDAO tokens on seller's behalf
tx = await LUsDAO.approve(PLUsDAO.address); 0;
txReceipt = await tx.wait(); 0;

// Post offer
let provision = await liquidityProvider.computeAskProvision();
let askReceipt = await liquidityProvider.newAsk({price: 2, volume: 3, fund: provision});

market.consoleAsks();
await printBalances(seller.address);
*/



/* Terminal 4 - taker using mangrove.js
source .env
node

// Limit the output to the given depth when printing results.
// We typically set this to 0 or 1.
//
// If you don't set this, the REPL will print A LOT of information after each command.
//
// It's typically better to assign results to a variable and then selectively
// print the parts of the result object that are relevant.
util.inspect.replDefaults.depth = 0;

// Load the .env file into process.env
// Any environment variables that were already set are not overriden.
var parsed = require("dotenv").config();

// Load the mangrove.js API
const { Mangrove, MgvToken, ethers } = require("@mangrovedao/mangrove.js");

// Connect to the chosen node provider
const provider = new ethers.providers.WebSocketProvider(
  // Change this to the appropriate env var for the chain you want to connect to
  process.env.LOCALHOST_URL
);

// Set up a wallet that will be used to sign tx's in the demo
let taker = new ethers.Wallet(process.env.LOCALHOST_TAKER_PRIVATE_KEY, provider);

// Connect to Mangrove
let mgv = await Mangrove.connect({ signer: taker });

// Connect to tokens
let UsUSD = mgv.token("UsUSD");
let UsDAO = mgv.token("UsDAO");
let LUsDAO = mgv.token("LUsDAO");
let PLUsDAO = mgv.token("PLUsDAO");
let MetaPLUsDAO = mgv.token("Meta-PLUsDAO");

// Util for printing relevant balances
async function printBalances(address) {
  console.group("Balances for " + address);
  for (var t of [UsUSD, UsDAO, LUsDAO, PLUsDAO, MetaPLUsDAO]) {
    let balance = await t.balanceOf(address);
    console.log(`${t.name}:\t\t${balance}`);
  }
  console.groupEnd();
}

await printBalances(taker.address);

// Connect to market
let market = await mgv.market({base: 'Meta-PLUsDAO', quote:'UsUSD'});
market.consoleAsks();

// Taker approves Mangrove for transfers of quote token
// This is required before buying
tx = await market.quote.approveMangrove(); 0;
await tx.wait(); 0;

// Buy LUsDAO tokens
let orderResult = await market.buy({volume:2, price:2});
orderResult.summary
*/

// This script deploys the Usual demo contracts
contract UsualDemoDeployer is Deployer {
  function run() public {
    address seller = getRawAddressOrName("SELLER_ADDRESS");
    address taker = getRawAddressOrName("TAKER_ADDRESS");

    uint sellerLUsDAOAmount = 10e18;
    uint takerUsUSDAmount = 100e18;

    IMangrove mgv = IMangrove(fork.get("Mangrove"));

    broadcast();
    TestToken usUSDToken =
      new TestToken({ admin: msg.sender, name: "Usual USD stable coin", symbol: "UsUSD", _decimals: 18 });
    fork.set("UsUSD", address(usUSDToken));

    broadcast();
    TestToken usDAOToken =
      new TestToken({ admin: msg.sender, name: "Usual governance token", symbol: "UsDAO", _decimals: 18 });
    fork.set("UsDAO", address(usDAOToken));

    broadcast();
    LockedWrapperToken lUsDAOToken =
      new LockedWrapperToken({ admin: msg.sender, name: "Locked Usual governance token", symbol: "LUsDAO", _underlying: usDAOToken });
    fork.set("LUsDAO", address(lUsDAOToken));

    broadcast();
    LockedWrapperToken pLUsDAOToken =
      new LockedWrapperToken({ admin: msg.sender, name: "Price-locked Usual governance token", symbol: "PLUsDAO", _underlying: lUsDAOToken });
    fork.set("PLUsDAO", address(pLUsDAOToken));

    broadcast();
    MetaPLUsDAOToken metaPLUsDAOToken =
      new MetaPLUsDAOToken({ admin: msg.sender, _name: "Meta Price-locked Usual governance token", _symbol: "Meta-PLUsDAO", pLUsDAOToken: pLUsDAOToken, mangrove: address(mgv) });
    fork.set("Meta-PLUsDAO", address(metaPLUsDAOToken));

    broadcast();
    PLUsMgvStrat pLUsMgvStrat =
      // new PLUsMgvStrat({ admin: msg.sender, mgv: mgv, pLUsDAOToken: pLUsDAOToken, usUSD: usUSDToken });
      new PLUsMgvStrat({mgv: mgv, pLUsDAOToken: pLUsDAOToken, metaPLUsDAOToken: metaPLUsDAOToken});
    fork.set("PLUsMgvStrat", address(pLUsMgvStrat));


    // Setup tx's. Placed after deployments to keep addresses stable
    // Activate PLUsMgvStrat
    IERC20[] memory tokens = new IERC20[](2);
    tokens[0] = IERC20(metaPLUsDAOToken);
    tokens[1] = IERC20(usUSDToken);
    broadcast();
    pLUsMgvStrat.activate(tokens);
    // FIXME: PLUsMgvStrat is single-user in this demo, so set seller to admin
    broadcast();
    pLUsMgvStrat.setAdmin(seller);

    // Tell Meta-PLUsDAO the address of PLUsMgvStrat
    broadcast();
    metaPLUsDAOToken.setPLUsMgvStrat(address(pLUsMgvStrat));

    // Mint tokens for seller and taker
    broadcast();
    usUSDToken.mint(taker, takerUsUSDAmount);
    broadcast();
    usDAOToken.addAdmin(address(lUsDAOToken)); // Allow LUsDAO to mint UsDAO
    broadcast();
    lUsDAOToken.mint(seller, sellerLUsDAOAmount);

    // Whitelistings
    //   PLUsDAO for LUsDAO
    broadcast();
    lUsDAOToken.addToWhitelist(address(pLUsDAOToken));
    //   Meta-PLUsDAO for PLUsDAO
    broadcast();
    pLUsDAOToken.addToWhitelist(address(metaPLUsDAOToken));
    //   PLUsMgvStrat for PLUsDAO
    broadcast();
    pLUsDAOToken.addToWhitelist(address(pLUsMgvStrat));

    outputDeployment();
  }
}
