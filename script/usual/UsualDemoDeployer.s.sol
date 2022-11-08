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
//   - PLUsDAO needed approvals/whitelisting:
//     - LUsDAO:
//       - whitelisted to allow taking/releasing custody of LUsDAO tokens
//       - approved to allow transfers from: seller
//   - Meta-PLUsDAO needed approvals/whitelisting:
//     - PLUsDAO:
//       - whitelisted to allow transfers and unlocks
//       - approved to allow transfers from: PLUsMgvStrat, Mangrove
//   - Price-Locking dApp approvals/whitelisting:
//     - PLUsDAO:
//       - whitelisted to allow locking
//     - PLUsMgvStrat:
//       - whitelisted to allow posting offers
//   - PLUsMgvStrat needed approvals/whitelisting:
//     - PLUsDAO:
//       - whitelisted to allow transfers
//       - approved to allow transfers from: seller
//   - Mangrove needed approvals/whitelisting:
//     - UsUSD:
//       - approved to allow transfers from: proxy/taker
//     - Meta-PLUsDAO:
//       - approved to allow transfers from: PLUsMgvStrat
//       

// DONE:
// - implement LUsDAO, PLUsDAO, Meta-PLUsDAO
// - consider whether TakerProxy is required
//   - for a demo, it shouldn't be needed and it makes mangrove.js less useful

// DEMO INSTRUCTIONS
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

# Deploy Usual contracts
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

/* Terminal 3 - mangrove.js
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

// This 'overrides' object specifies a high=fast gas price and can be passed
// to mangrove.js API function that send tx's.
// This can speed up demos against a real chain.
// For local chains/forks, this can be omitted.
const overrides = { gasPrice: ethers.utils.parseUnits("60", "gwei") };

// Connect to the chosen node provider
const provider = new ethers.providers.WebSocketProvider(
  // Change this to the appropriate env var for the chain you want to connect to
  process.env.LOCALHOST_URL
);

// Set up a wallet that will be used to sign tx's in the demo
let taker = new ethers.Wallet(process.env.LOCALHOST_TAKER_PRIVATE_KEY, provider);

// Connect the API to Mangrove
let mgv = await Mangrove.connect({ signer: taker });

// Connect to a specific market
let market = await mgv.market({base: 'Meta-PLUsDAO', quote:'UsUSD'});
market.consoleAsks();
market.consoleBids();
*/

// This script deploys the Usual demo contracts
contract UsualDemoDeployer is Deployer {
  function run() public {
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
    PLUsMgvStrat pLUsMgvStrat =
      new PLUsMgvStrat({admin: msg.sender, mgv: mgv, pLUsDAOToken: pLUsDAOToken, usUSD: usUSDToken });
    fork.set("PLUsMgvStrat", address(pLUsDAOToken));

    broadcast();
    MetaPLUsDAOToken metaPLUsDAOToken =
    new MetaPLUsDAOToken({ admin: msg.sender, _name: "Meta Price-locked Usual governance token", _symbol: "Meta-PLUsDAO", pLUsDAOToken: pLUsDAOToken, mangrove: address(mgv), pLUsMgvStrat: address(pLUsMgvStrat) });
    fork.set("Meta-PLUsDAO", address(metaPLUsDAOToken));

    outputDeployment();
  }
}
