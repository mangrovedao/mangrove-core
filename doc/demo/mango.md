# MANGO DEMO INSTRUCTIONS

This document describes how to do a Mango demo on a local chain and a mangrove.js REPL.

# TODO

This document is not yet complete, the following remains to be done:

- verify market parameters wrt density
- take orders and show what Mango has done in response
- refactor this document, so that the prerequisites for deploying Mangrove and opening a market is an independent and self-contained demo guide

# Deployment commands

```sh
# cd mangrove-core
source .env

# Deploy Mangrove and periphery contracts
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast MangroveDeployer

# Deploy MangroveOrder. It's not used in the demo but is required by mangrove.js
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast MangroveOrderDeployer

# Temp workaround for mangrove.js not deploying multicall: Deploy Multicall
./deployRemoteMulticall.sh

# Deploy tokens
NAME="Wrapped Ether" \
SYMBOL=WETH \
DECIMALS=18 \
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast ERC20Deployer

NAME="Circle USD" \
SYMBOL=USDC \
DECIMALS=6 \
WRITE_DEPLOY=true forge script --fork-url $LOCALHOST_URL --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY --broadcast ERC20Deployer

# Configure WETH/USDC market
# TODO: These numbers should be verified
TKN1=WETH \
TKN2=USDC \
TKN1_IN_GWEI=$(cast ff 9 2000) TKN2_IN_GWEI=$(cast ff 9 1) \
FEE=0 forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  ActivateMarket
```

# Deploying Mango on WETH, USDC market

We want to deploy a Mango strat on the WETH/USDC market. We plan to do market making on the price range `[200 USDC/ETH, 4000 USDC/ETH]` (with 100 offers).

## Deploy script

We first set up the environment variables we need to pass to the deploy script:

```sh
# Base, quote tokens
export BASE=WETH
export QUOTE=USDC
# Pmin = QUOTE_0/BASE_0 (initial price is 200 USDC/ETH)
export BASE_0=$(cast ff 18 1)
export QUOTE_0=$(cast ff 6 200)
# Number of price divisions
export NSLOTS=100
# Price increment should be such that 200 + pr_incr * NSLOTS = 4000
export PRICE_INCR=$(cast ff 6 38)
```

One can call the deploy script (assuming a local node is running on localhost):

```sh
forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  MangoDeployer
```

## Mango status

The newly deployed Mango should be in the following state:

- It has already approved Mangrove for pulling base and quote tokens during offer logic.
- It has deployed and bound a simple router that will source liquidity from deployer's account (see [approvals](#approvals)).
- Deployer is router's admin.

## Approvals

Deployer needs to approve Mango's router, we do this in the console by getting Mango LP on the (WETH,USDC) market:

```javascript
// Limit the output to the given depth when printing results.
// We typically set this to 0 or 1.
//
// If you don't set this, the REPL will print A LOT of information after each command.
//
// It's typically better to assign results to a variable and then selectively
// print the parts of the result object that are relevant.
util.inspect.replDefaults.depth = 0;

// Load the mangrove.js API
const { Mangrove, MgvToken, ethers } = require("@mangrovedao/mangrove.js");

// Connect to the chosen node provider
const provider = new ethers.providers.WebSocketProvider(
  // Change this to the appropriate env var for the chain you want to connect to
  process.env.LOCALHOST_URL
);

// Set up a wallet that will be used to sign tx's in the demo
let seller = new ethers.Wallet(
  process.env.LOCALHOST_SELLER_PRIVATE_KEY,
  provider
);

// Connect to Mangrove
let mgv = await Mangrove.connect({ signer: seller });

let market = await mgv.market({ base: "WETH", quote: "USDC" });
let mango = await mgv.offerLogic("Mango_WETH_USDC").liquidityProvider(market);
let tx = await mango.approveBids();
await tx.wait();
tx = await mango.approveAsks();
await tx.wait();
```

# Initializing Mango

After the previous step, we can now ask Mango to populate Mangrove's (WETH,USDC) market with offers. To do this we will use another script whose environment variables are as follows:

```sh
# sets the default volume for bids
export DEFAULT_BASE_AMOUNT=$(cast ff 18 0.8)
# sets the default volume for asks
export DEFAULT_QUOTE_AMOUNT=$(cast ff 6 1000)
# index beyond which Mango will start asking
export LAST_BID_INDEX=$(($NSLOTS/2))
# number of offers posted per tx
export BATCH_SIZE=10
# multiplier of Mangrove's gasprice to provision offers
export COVER_FACTOR=2
```

then run the script using:

```sh
MANGO="Mango_WETH_USDC" \
forge script \
  --fork-url $LOCALHOST_URL \
  --private-key $LOCALHOST_DEPLOYER_PRIVATE_KEY \
  --broadcast \
  InitMango
```
