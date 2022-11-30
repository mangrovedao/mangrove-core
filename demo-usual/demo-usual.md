# USUAL DEMO INSTRUCTIONS

This is a demo of how Usual's price-lock market could work on Mangrove.

The demo uses a local chain with Mangrove + extra demo contracts and mangrove.js for interactions.

## Prerequisites

- Mangrove dev environment
- Clone of the `mangrove-core` repo with the `demo/usual` branch checked out and built.
- Empty `sandbox` folder

The following `.env` file should be in the `mangrove-core` and `sandbox` folders:

```sh
export LOCALHOST_URL=http://127.0.0.1:8545
export LOCALHOST_MNEMONIC="test test test test test test test test test test test junk"

export LOCALHOST_DEPLOYER_ACCOUNT_ADDRESS="0xf39fd6e51aad88f6f4ce6ab8827279cfffb92266"
export LOCALHOST_DEPLOYER_PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"

export LOCALHOST_TAKER_ADDRESS="0x70997970c51812dc3a010c7d01b50e0d17dc79c8"
export LOCALHOST_TAKER_PRIVATE_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"

export LOCALHOST_SELLER_ADDRESS="0x3c44cdddb6a900fa2b585dd299e03d12fa4293bc"
export LOCALHOST_SELLER_PRIVATE_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
```

## Demo setup

Create the following terminals:

- Terminal 1 - local chain
- Terminal 2 - deployment and configuration of contracts
- Terminal 3 - seller using mangrove.js
- Terminal 4 - taker using mangrove.js

### Terminal 1: Local chain

Run the following commands to start a local chain:

```sh
# cd mangrove-core
source .env
anvil --port 8545 --mnemonic $LOCALHOST_MNEMONIC
```

### Terminal 2 - deploy & configure contracts

Run the following commands to deploy Mangrove, the demo contracts, and open the Meta-PLUsDAO/UsUSD market:

```sh
# cd mangrove-core
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
```

### Terminal 3 - Seller using mangrove.js

Setup the `sandbox` folder:

```sh
# Create the directory
mkdir sandbox && cd sandbox
# Init npm
npm init -y
npm install @mangrovedao/mangrove.js
# Create .env file
cat >.env
# paste .env contents here, see further up
# press ctrl-d
```

Start the nodejs REPL:

```sh
source .env
node
```

### Terminal 4 - taker using mangrove.js

The taker also runs the nodejs REPL in the `sandbox` folder:

```sh
# cd sandbox
source .env
node
```

## Doing the demo

Terminals 1 & 2 need not be shown while doing the demo.

Terminals 3 & 4 (seller and buyer) can be shown side-by-side.

### Step 1: Seller connects to Mangrove and price-locks LUsDAO tokens

Enter the following into Terminal 3:

```js
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
let market = await mgv.market({ base: "Meta-PLUsDAO", quote: "UsUSD" });
market.consoleAsks();

// Connect to PLUsMgvStrat
let plusMgvStrat = mgv.offerLogic("0x610178dA211FEF7D417bC0e6FeD39F05609AD788");
// Use liquidity provider, ie. the PLUsMgvStrat connected to a market
let liquidityProvider = await plusMgvStrat.liquidityProvider(market);

// Approve PLUsMgvStrat to transfer Meta-PLUsDAO tokens on seller's behalf
let tx = await liquidityProvider.approveAsks();
0;
let txReceipt = await tx.wait();
0;
// Approve Meta-PLUsDAO to transfer PLUsDAO tokens on seller's behalf
tx = await PLUsDAO.approve(MetaPLUsDAO.address);
0;
txReceipt = await tx.wait();
0;
// Approve PLUsDAO to transfer LUsDAO tokens on seller's behalf
tx = await LUsDAO.approve(PLUsDAO.address);
0;
txReceipt = await tx.wait();
0;

// Post offer
let provision = await liquidityProvider.computeAskProvision();
let askReceipt = await liquidityProvider.newAsk({
  price: 2,
  volume: 3,
  fund: provision,
});

// Inspect the order book
market.consoleAsks();
// Print the seller's balances
await printBalances(seller.address);
```

### Step 2: Buyer connects to Mangrove and buys some LUsDAO tokens

Enter the following JS code into Terminal 4:

```js
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
let taker = new ethers.Wallet(
  process.env.LOCALHOST_TAKER_PRIVATE_KEY,
  provider
);

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
let market = await mgv.market({ base: "Meta-PLUsDAO", quote: "UsUSD" });
market.consoleAsks();

// Taker approves Mangrove for transfers of quote token
// This is required before buying
tx = await market.quote.approveMangrove();
0;
await tx.wait();
0;

// Buy LUsDAO tokens
let orderResult = await market.buy({ volume: 2, price: 2 });
orderResult.summary;

// Inspect taker's balances
await printBalances(taker.address);
```

### Step 3: Seller inspects her balances and the order book

In Terminal 3, enter the following commands:

```js
// Inspect the order book
market.consoleAsks();
// Print the seller's balances
await printBalances(seller.address);
```
