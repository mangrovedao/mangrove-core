# Deploying Mango on WETH, USDC market

We want to deploy a Mango strat on the (WETH, USDC) market. We plan to do market making on the price range `[200 USDC/ETH, 4000 USDC/ETH]` (with 100 offers).

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
forge script --fork-url $LOCALHOST_URL --broadcast MangoDeployer
```

## Mango status

The newly deployed Mango should be in the following state:

- It has already approved Mangrove for pulling base and quote tokens during offer logic.
- It has deployed and bound a simple router that will source liquidity from deployer's account (see [approvals](#approvals)).
- Deployer is router's admin.

## Approvals

Deployer needs to approve Mango's router, we do this in the console by getting Mango LP on the (WETH,USDC) market:

```javascript
let market = await Mangrove.market({ base: "WETH", quote: "USDC" });
let mango = await Mangrove.offerLogic("Mango_WETH_USDC").liquidityProvider(
  market
);
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
forge script --fork-url $LOCALHOST_URL --broadcast InitMango
```
