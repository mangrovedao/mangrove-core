# Audit trail for Mangrove v2

## Audit scope: all files matching

- src/core/\*
- lib/core/\*

As usual running `yarn doc` then opening `doc/MgvDoc.html` will give you better-formatted view of the code.

## Overview

The goal of Mangrove v2 is constant-time offer insertion & update.

**Why we need it**: when an `offer` is executed, it may insert or update other offers. Since `offer.gasreq` is fixed, these changes must take a constant amount of gas. In Mangrove v1, offer insertion and update walks a doubly linked list, so it does not use a constant amount of gas.

**How we get it**: by structuring offers in a fixed-height tree, with 'bins' at the leafs. Each bin is a doubly linked list. When an offer is inserted or moved, it gets appended at the end of the appropriate bin. Equally-priced offers are no longer sorted by their density (the density of an offer is the amount of tokens they promise per unit of gas they consume).

Contract inheritance:

```
                                   HasMgvEvents
                                        │
                                        │
                                        │
                                    MgvCommon
                                        │
                       ┌────────────────┴──────────┐
                       │                           │
                 MgvHasOffers                      │
                       │                           │
           ┌───────────┴──────────┐                │
           │                      │                │
    MgvOfferTaking         MgvOfferMaking          │
           │                      │                │
           │                      │                │
MgvOfferTakingWithPermit          │                │
           │                      │                │
           └───────────┬──────────┘                │
                       │                           │
                       │                           │
                AbstractMangrove                   │
                       │                           │
                       ▼                           ▼
                    Mangrove                  MgvAppendix
```

Overview of the changes between v1 and v2:

## Prices are discrete and granularity is configurable

Since prices in v2 are structured in a tree, they must be less granular than before. We use a relative-tick-based approach, as in Uniswap v3+. An offer at tick `t` has price ~`1.0001^t`.

In addition, "`(outbound,inbound)` token pairs" are now "`(outbound,inbound,tickSpacing)` offer lists". As in Uniswap, a high `tickSpacing` decreases the price granularity.

## Offer specify a tick

Offers no longer specify a `gives,wants`. They now specify a `gives,tick`. Ticks are in the -887272;887272 range, so a tick fits on 21 bits. The limit for `offer.gives` has increased from 96 to 127 bits. `offer.wants` is ~`offer.gives * 1.0001^tick`.

## Market orders use a true limit price

Market orders do not specify `takerGives` and `takerWants` amounts. Instead, they specify a `fillVolume` amount and a `tick`. Depending on the chosen mode of operation, `fillVolume` can represent an amount to buy, or an amount to sell. The amount limit has decreased from 160 bits to 127 bits.

With this new way of specifying amounts and prices, the price induced by tick is now understood as a classic 'limit price': no offer with a price above ~`1.0001^tick` will be considered by the market order. In the v1 version of Mangrove, the price induced by `takerGives,takerWants` was not a true limit price but a 'limit average price'.

## The volume-based API is still available

To make the transition easy, the volume-based API for market orders, offer insertion and offer update is still available. It internally converts to the `volume,tick` representation.

The volume-based version of the market order also interprets the price induced by `takerWants,takerGives` as a true limit price (not as a limit average price).

## Market orders are limited by recursion depth and by wasted gas

The `maxRecursionDepth` parameter bounds the number of offers that can be executed before the market order stop (without revert). Another parameter, `maxGasreqForFailingOffers`, bounds the sum of `gasreq` of executed failing offers. Once above that number, the market order stops (without revert).

If a segment of bad offers is low-gas but long enough to overflow the EVM stack, any market order would revert and leave the bad offers in place. If a segment of bad offers consumes more gas than the block gas limit, any market order would revert and leave the bad offers in place.

The recursion and gas for failing offer parameters, if well-configured, prevent multiple failing offers from clogging the order book indefinitely.

## Several parameter sizes have changed

### Density is stored as a float and presented as a fixed-point number

To reduce gas use, we cache more data than before in the `local` storage slot of each market. To make some room, the `density` parameter is no longer a 112 bit integer but a 9-bit floating-point number. It has a 2-bit mantissa and a 7-bit exponent. The minimum increment between two densities is 25%, but we do not need more precision than that.

That change in representation also extends the available `density` range to fractional values (there are plausible scenarios where `density` should be < 1).

The external representation of density is not a float but a 96.32 fixed-point number. It is easier to manipulate that way.

### `offer_gasbase` is now `kilo_offer_gasbase`

The unit is no longer gas but kilogas, and it fits on 9 bits (formerly 24 bits).

### `gasprice` is now in Mwei

The unit is no longer gwei but mwei, and it fits on 26 bits (formerly 16 bits).

## Sniping has been restricted to Cleaning

Offers can no longer be executed individually ('sniping'), unless their execution ends in failure. Otherwise, their execution is reverted. We rename 'sniping' to 'cleaning'.

We could not find a legitimate use for snipe other than the cleaning of failing offers. Also, some strategies could be broken by the full snipe functionality.

## Makers cannot read the offer list during `makerExecute`

Makers can no longer read the offer list during `makerExecute`` for the following reasons:

- Prevent makers from distinguishing between a market order and a cleaning. To prevent makerExecute from detecting cleaning
- Avoid the gas cost of keeping the offer list up-to-date for `makerExecute``. A number of optimizations are in place which mean that local, leafs, and levels may not be up-to-date.

Two measures have been added to achieve this:

- The existing offer list lock is now enforced as a read-lock as well in all the view functions.
- All fields in the `SingleOrder` struct that pertain to the offer list/tick tree structure are cleared (set to zero) before they are passed to `makerExecute`.

## Mangrove is split into two contracts and uses delegatecall internally

Mangrove v2 has too much code to fit in a single contract. To overcome the issue, the contract is split in 2. All view functions and all governance functions are deployed at another address. This happens in the constructor of Mangrove. When Mangrove receives a call with an unknown selctor, it delegatecalls to that other address.
