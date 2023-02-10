# Contracts in scope for the audit

## Kandel and aave router

### src/strategies/offer_maker/market_making/kandel/Kandel.sol

The direct Kandel contract without a router which utilizes the other building blocks.

### src/strategies/routers/integrations/AavePooledRouter.sol

A new type of router able to deposit and withdraw funds on AAVE v3. This router is pooling liquidity of all the maker contracts that are bound to it. Balance of each maker is maintained by means of share balances.

### src/strategies/offer_maker/market_making/kandel/AaveKandel.sol

The AavePooledRouter version of the Kandel contract

### src/strategies/offer_maker/market_making/kandel/KandelSeeder.sol

A contract to do permissionless deploy the Kandel and AaveKandel contracts and bind to a shared router

### Dependencies

Kandel type strategies and Aave router have the following dependencies:

- AbstractKandel: Core abstract functions offered by Kandel strats
- GeometricKandel: Implements the geometric price progression used in the Kandel strat without storing the actual prices
- CoreKandel: Implements the core of the Kandel strat which updates a dual offer whenever an offer is taken, but is agnostic to the actual price distribution.
- TradesBaseQuotePair: Implements helper functions for trading a base, quote pair of tokens using bid and ask terminology.
- HasIndexedBidsAndAsks: Implements the ability to have a [0..length] indexed set of offers on Mangrove for both bids and asks
- DirectWithBidsAndAskDistribution: Adorns the Direct strat with indexed bids and asks and allows the offers to be populated according to a given base and quote distribution.
- AbstractRouter: the root contract for routers
- AaveV3Lender: a module that implements AAVE v3 interaction capacities.
- Direct: the basic strat building block for private maker contracts (as opposed to Forwarder contracts)
- MangroveOffer: the root contract for strats (already audited, see minor changes below)
- AccessControlled: admin management (already audited, unchanged)

## Minor changes to already audited code

### src/strategies/MangroveOffer.sol

- external storage contract is removed. It was planned for future extension of the strat that would yield a too large code, but it was detrimental to gas efficiency.
- cosmetic changes of variables and constant names
- `logRepostStatus` is called at the end of `__posthookSuccess__` in order to log unexpected failure to repost
- `__reserve__` hook was removed (no clear use case and potentially bug prone). As a consequence offer owner in Forwarder strats (such as MangroveOrder) no longer have strat ready remapping of their address. Direct strats use a different scheme (reserve id).
- `checkList` is no longer calling router's checklist. This will is done in the ad hoc hooks in Direct and Forwarder.
- `withdrawFromMangrove` is made public to allow offer logic to withdraw funds if needed

### src/strategies/MangroveOrder.sol

- A public implementation of `_retractOffer` is now provided (see changes in IOfferLogic and Forwarder)
- Since the `__reserve__` hook was removed, references to `reserve(msg.sender)` have been replaced by `msg.sender`
- We adapted the call to `_newOffer` in order to ignore the returned `bytes32`.

### src/strategies/interfaces/IOfferLogic.sol

- `retractOffer` is no longer a public function required by the IOfferLogic interface. Internal `_retractOffer` is provided both for `Forwarder` and `Direct` strats and needs to be exposed (see `MangroveOrder` changes).

### src/strategies/offer_forwarder/Forwarder.sol

- `_newOffer`'s computation of new gasprice is factored out for clarity in `deriveAndCheckGasprice`. The computation is unchanged. Function now returns both the `offerId` assigned by Mangrove to the new offer and a byte32 which is non empty when Mangrove reverted with a reason, and `noRevert` argument was set to `true`.
- giving `max(uint).type` in the `gasreq` argument of both `_updateOffer` and `_newOffer` is no longer interpreted as requiring `offerGasreq()`.
- `retractOffer` is no longer a public function of Forwarder. An internal `_retractOffer` is provided for Forwarder starts (in accordance to the IOfferLogic interface change above).
- Offer owner can no longer be mapped to another address via the `__reserve__` hook that has disappeard (see `MangroveOffer` change). It has no impact on `MangroveOrder` which was not using this hook.

### src/strategies/routers/AbstractRouter.sol

- external storage contract is removed (see MangroveOffer).
- Cosmetic changes in naming. In particular auth error messages are made uniform. `reserve` has been replaced by `reserveId` to take into account the fact that routers interpret this field differently (SimpleRouter forwards liquidity to this address, AavePooledRouter just use the address to label shares of the pool). `reserveBalance` is now called `balanceOfReserve` and requires `reserveId` argument.
- Log emition when binding/unbinding to a maker contract.
- router's checklist has been simplified and can be called from an arbitrary address.

### src/strategies/routers/SimpleRouter.sol

- propagating naming scheme changes from AbstractRouter. We use `owner` instead of `reserveId` in simple router to reflect the fact that funds are transfered to offer owners.

### src/strategies/utils/TransferLib.sol

- `transferTokensFrom` and `transferTokens` where added as plural implementation of `transferToken` and `transferTokenFrom` of the same library (in order to allow mutliple transfers in the same call).
- note that these function do not return success but revert on failure (to avoid returning an unwieldy array of booleans).