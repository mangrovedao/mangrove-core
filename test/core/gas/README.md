# Gas tests for the core protocol

Gas tests be run with `-vv` so correct gas estimates are shown.

To list gas usage for all scenarios run `yarn gas-measurement`. This generates `gas-measurement.{json,csv}` files with the gas measurements in the `out` folder.

To get a diff in gas measurements (eg with different optimization settings or different code versions) first run `yarn gas-measurement` in the before setup, and then run `yarn gas-measurement --diff` in the after setup. This will generate `out/gas-measurement-diff.{json,csv}` files with the gas measurements before and after as well as the delta for each test.

We test gas usage for various scenarios. This can be used to determine gas usage for a strat's `makerExecute` or `makerPosthook` functions. The absolute values are rarely used, instead a strat builder should verify their gas usage in some specific scenario (e.g. with posthook updating the same offer list as its taken on, where the offer list has other offers on the same bin as a new offer is created on) and then compare deltas to other scenarios tested here and use it to set a `gasreq` for their strat which covers the desired worst-case scenarios. The gas measurements are for the inner-most operation.

The measured functions often take a `logPrice` argument, but the gas differences are related to differences in the `bin` structures. So the actual `logPrice` is not important, it is the resulting `bin` that is important for gas estimates.

## Scenarios

The main functions to test are:

- `newOffer` O(1)
- `updateOffer` O(1) (live (different localities, higher/lower gasreq) or dead (deprovisioned or not))
- `retractOffer` O(1) (deprovision or not)
- `marketOrder` O(n) for n offers taken.
- `cleanByImpersonation` O(1) but depends on gasreq.

These functions can be invoked from various places that affect their gas cost due to hot vs cold access:

- `makerExecute`
- `makerPosthook` (with failed or successful `makerExecute`)
- `external` (i.e. from other contract or EOA)

For `makerPosthook` the functions can be executed on

- different offer list from the one being executed (cold)
- same offer list as the one being executed (more hot)

For `makerExecute` the same offer list cannot be touched due to being locked, and for `external` the offer list and Mangrove can be considered cold.

For these reasons we test `newOffer`, `updateOffer`, and `retractOffer` from `makerPosthook` on the same offer list as the one for the offer being executed as a semi-hot scenario, and from `external` as a cold scenario. Actual usage when accessing a different offer list from, e.g., `makerExecute` from inside the same Mangrove instance will cost slightly less due to Mangrove being warm, but we disregard that.

Additionally, the state of the offer lists affect execution:

- always empty (completely new)
- now empty (out of liquidity)
- with offer on same bin as operation. That is: same price.
- with offer on same leaf as operation. Can be at most up to a price scale difference of `BP^(LEAF_SIZE)`
- with offer on same level1 as operation. Can be at most up to a price scale difference of `BP^(LEAF_SIZE * LEVEL1_SIZE)`
- with offer on same level2 as operation. Can be at most up to a price scale difference of `BP^(LEAF_SIZE * LEVEL1_SIZE * LEVEL2_SIZE)`
- with offer on same level3 as operation. Can be at most up to a price scale difference of `BP^(LEAF_SIZE * LEVEL1_SIZE * LEVEL2_SIZE * LEVEL3_SIZE)`
- with offer on same root as operation. Can be any difference up to max bin.

The non-empty ones are referred to as "various bin-distances".

Also, the offer can be better or worse than current best offer (affecting whether to update `local`). This is captured in the helper `TickTreeBoundariesGasTest`.

From `makerPosthook` on the same offer list, then the gas cost is also affected by how warm the affected branch is which depends on where the taken offer is relative to the operation's offer (again: same bin, leaf, level1, level2, level3, root).

For each of the main functions this leads to the scenarios listed in the next sections.

### `newOffer`

- `makerPosthook`
  - on offer success
    - now empty offer list (out of liquidity): `PosthookSuccessNewOfferSameList_WithNoOtherOffersGasTest`
    - offer exists on offer list with new offer at various bin-distances: `PosthookSuccessNewOfferSameList_WithOtherOfferGasTest`
    - offer also exists on same bin as new offer price (only higher bins tested): `PosthookSuccessNewOfferSameList_WithOtherOfferAndOfferOnSameTickTreeBoundariesGasTest`
    - two offers posted, one at same bin as taken offer, gas measured of second at various bin-distances: `PosthookSuccessNewOfferSameList_WithPriorNewOfferAndNoOtherOffersGasTest`
  - on offer failure
    - same as offer success: Named `PosthookFailureNewOfferSameList_*` instead of `PosthookSuccessNewOfferSameList_*`. (has exact same gas costs)
- `external`
  - always empty offer list (completely new market): `ExternalNewOfferOtherOfferList_AlwaysEmptyGasTest`
  - same as `makerPosthook`->on offer success. Named: `ExternalNewOfferOtherOfferList_*` instead of `PosthookSuccessNewOfferSameList_*`.

### `updateOffer`

The `makerPosthook`->on offer success tests all update the taken offer. See the specific `external` scenarios and use deltas from those to extrapolate to other scenarios.

- `makerPosthook`

  - on offer success
    - same as for `newOffer`: Named `PosthookSuccessUpdateOfferSameList_*` instead of `PosthookSuccessNewOfferSameList_*`.
  - on offer failure
    - skipped as `newOffer` tests did not show gas difference. Deprovisioned offers are covered separately.

- `external`

  - similar scenarios as `makerPosthook`->on offer success. Named `ExternalUpdateOfferOtherOfferList_*` instead of `PosthookSuccessNewOfferSameList_*` and adapted to update over new.

    - now empty offer list (out of liquidity) - simply a repost of a taken (dead) offer with same `gasreq` and no `deprovision` since offer was successfully taken.
    - offer exists on offer list with new offer at various bin-distances - the updated offer is initially live at same bin as other offer.
    - offer also exists on same bin as new offer price
    - two offers posted at middle, both updated - first to same bin, second at various bin-distances with gas measured.

  - live vs dead vs gas
    - update dead deprovisioned offer to far away price: `ExternalUpdateOfferOtherOfferList_DeadDeprovisioned`
    - update dead provisioned offer to far away price: `ExternalUpdateOfferOtherOfferList_DeadProvisioned`
    - update live offer to far away price, same, higher, or lower `gasreq` (and thereby gasprice): `ExternalUpdateOfferOtherOfferList_Gasreq`

### `retractOffer`

Retracting offers is different from new and updated offers in that the retraction does not have a price parameter. We therefore reduce the number of scenarios.

- `makerPosthook`

  - on offer success
    - retract offer at various bin-distances from taken offer: `PosthookSuccessRetractOfferSameList_WithOtherOfferGasTest`
    - retract offer after already retracting another offer near taken offer: `PosthookSuccessRetractOfferSameList_WithPriorRetractOfferAndOtherOffersGasTest`

- `external`
  - retract last offer from offer list - with and without deprovision: `ExternalRetractOfferOtherOfferList_WithNoOtherOffersGasTest`
  - retracting an offer when another offer exists at various bin-distances to the offer's price: `ExternalRetractOfferOtherOfferList_WithOtherOfferGasTest_*`
  - retracting an offer when another offer exists at various bin-distances to the offer price but also on the same bin: `ExternalRetractOfferOtherOfferList_WithOtherOfferAndOfferOnSameTickTreeBoundariesGasTest_*`
  - retracting a second offer at various bin-distances after retracting an offer at MIDDLE_LOG_PRICE: `ExternalRetractOfferOtherOfferList_WithPriorRetractOfferAndNoOtherOffersGasTest`

### `marketOrder`

We do not consider usage from maker contracts since it is unbounded, so only external calls.

- `external`
  - Taking the last offer so offer list becomes empty in various cases: `ExternalMarketOrderOtherOfferList_WithNoOtherOffersGasTest`
  - Taking an offer, moving the price further and further through bins to next available offer: `ExternalMarketOrderOtherOfferList_WithOtherOfferGasTest`
  - Taking multiple offers with increasing number of offers on same bin: `ExternalMarketOrderOtherOfferList_WithMultipleOffersAtSameBin`
  - Taking some offers, moving the price further and further through bins: `ExternalMarketOrderOtherOfferList_WithMultipleOffersAtManyBins`

### `offer_gasbase`

`OfferGasBaseBaseTest` outputs gas usage for a market order which takes the last available offer on an offer list. It also outputs the current estimate used for gasbase which comes from `ActivateSemibook`.

### `cleanByImpersonation`

We do not expect clean to be used from maker contracts, so only external calls.

- `external`
  - same scenarios as `retractOffer` named `ExternalCleanOtherOfferList_*` instead of `ExternalRetractOfferOtherOfferList_*`.

### `gasreq`

Strats will need to set a gasreq, for this the `OfferGasReqBaseTest` in `@mgv/test/lib/gas/OfferGasReqBase.t.sol` can be implemented. See examples in the strat library.
