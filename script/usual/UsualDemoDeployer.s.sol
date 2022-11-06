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

// DONE:
// - implement LUsDAO, PLUsDAO, Meta-PLUsDAO
// - consider whether TakerProxy is required
//   - for a demo, it shouldn't be needed and it makes mangrove.js less useful

// DEMO INSTRUCTIONS
// All terminals are in mangrove-core on the demo/usual branch
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
# FIXME: Hoping that we don't need to specify addresses
# TKN1=0x63E537A69b3f5B03F4f46c5765c82861BD874b6e \
# TKN2=0xD59A51bE32eA35Db72De6A3Eb88bf2C56811f57c \
TKN1=Meta-PLUsDAO \
TKN2=UsUSD \
# The following params are used to infer density parameters. The values are the price of the two tokens in native gwei.
TKN1_IN_GWEI=$(cast ff 9 1) TKN2_IN_GWEI=$(cast ff 9 1) \
FEE=0 forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  ActivateMarket
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
