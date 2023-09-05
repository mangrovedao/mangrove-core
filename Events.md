# Introduction

Events in solidity is a hard thing to do in a optimal way. If you look at it as a purely gas efficient issue, you want to emit as few events as possible and with as few fields as possible. But as events also has to be usable for an off chain user, then doing this is not always the best solution.

We tried to list the main points that we would like to do with events.

1. Use as little gas as possible
2. An indexer should be able to keep track of the state of Mangrove.
3. Doing RPC calls directly, should be able to find offers and other information based on offerlist, maker, taker, offer id, etc.

These 3 points all have there own direction and it is therefore not possible to find a solution that is optimal for all 3 points.
We have therefore tried to find a solution that is a good balance between the all 3 points.

## Events

### Approval

This is emitted when a user permits another address to use a certain amount of its funds to do market orders, or when a user revokes another address to use a certain amount of its funds.

Approvals are based on the pair of outbound and inbound token. Be aware that it is not offerlist bases, as an offerlist also holds the tickscale.

We emit `outbound` token, `inbound` token, `owner`, msg.sender (`spender`), `value`. Where `owner` is the one who owns the funds, `spender` is the one who is allowed to use the funds and `value` is the amount of funds that is allowed to be used.

Outbound, inbound and owner is indexed, this way one can filter on these fields when doing RPC calls. If we could somehow combine outbound and inbound into one field, then we could also index the spender.

### Credit

This is emitted when a user's account on Mangrove is credited with some native funds, to be used as provision for offers.

It emits the `maker`'s address and the `value` credited

The `maker` address is indexed so that we can filter on it when doing RPC calls.

These are the scenarios where it can happen:

- Fund Mangrove directly
- Fund Mangrove when posting an offer
- When updating an offer
  - Funding Mangrove or
  - the updated offer needs less provision, than it already has. Meaning the user gets credited the difference.
- When retracting an offer and deprovisioning it.Meaning the user gets credited the provision that was locked by the offer.
- When an offer fails. The remaining provision gets credited back to the maker

A challenge for an indexer is to know how much provision each offer locks. With the current events, an indexer is going to have to know the liveness, gasreq and gasprice of the offer. If the offer is not live, then also know if it has been deprovisioned. And know what the gasbase of the offerlist was when the offer was posted. With this information an indexer can calculate the exact provision locked by the offer.

Another information that an indexer cannot deduce, is in what scenario the credit event happened. E.g. We don't know if the credit event happened because an offer failed or if the user simply funded Mangrove.

### Debit

This is emitted when a user's account on Mangrove is debited with some native funds.

It emits the `maker`'s address and the `value` debited.

The `maker` address is indexed so that we can filter on it when doing RPC calls.

These are the scenarios where it can happen:

- Withdraw funds from Mangrove directly
- When posting an offer. The user gets debited the provision that the offer locks.
- When updating an offer and it requires more provision that it already has. Meaning the user gets debited the difference.

Same challenges as for Credit

### Kill

Emitted when the Mangrove instance is killed

### NewMgv

Emitted when a new Mangrove is deployed.

### OrderStart

This event is emitted when a market order is started on Mangrove.

It emits the `offerlist key`, the `taker`, the `maxLogPrice`, `fillVolume` and `fillWants`.

The fields `offerlist key` and `taker` are indexed, so that we can filter on them when doing RPC calls.

By emitting this an indexer can keep track of what context the current market order is in. E.g. If a user starts a market order and one of the offers taken also starts a market order, then we can in an indexer have a stack of started market orders and thereby know exactly what offerlist the order is running on and the taker.

By emitting `maxLogPrice`, `fillVolume` and `fillWants`, we can now also know how much of the market order was filled and if it matches the price given. See OrderComplete for more.

### OfferFail(WithPosthookData)

This event is emitted when an offer fails, because of a maker error.

It emits `offerlist key`, `taker`, `maker`, the `offerId`, the offers `wants`, `gives`, `penalty` and the `reason` for failure. `Offer list key`, `taker` and `maker` are all fields that we do not need, in order for an indexer to work, as an indexer will be able the get that info from the former `OrderStart` and `OfferWrite` events. But in order for RPC call to filter on this, we need to emit them. Those 3 fields are indexed for the same reason.

If the posthook of the offer fails. Then we emit `OfferFailWithPosthookData` instead of just `OfferFail`. This event has one extra field, which is the reason for the posthook failure. By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics.

This event is emitted doring posthook end, we wait to emit this event to the end, because we need the information of `penalty`, which is only available at the end of the posthook. This means that `OfferFail` events are emitted in reverse order, compared to what order they are taken. This is do to the way we handle posthooks. The same goes for `OfferSuccess`.

By emitting this event, an indexer can keep track of, if an offer failed and thereby if the offer is live. By emitting the wants and gives that the offer was taken with, then an indexer can keep track of these amounts, which could be useful for e.g. strategy manager, to know if their offers fail at a certain amount.

### OfferSuccess

This event is emitted when an offer is successfully taken. Meaning both maker and taker has gotten their funds.

It emits the `offerlist key`, `taker` address, `maker` address, the `offerId` and the `takerWants` and `takerGives` that the offer was taken at. Just as for `OfferFail`, the `offerlist key`, `taker` and `maker` are not needed for an indexer to work, but are needed for RPC calls. So they are emitted and indexed for that reason. Just like `OfferFail` this event is emitted during posthook end, so it is emitted in reverse order compared to what order they are taken. This event could be emitted at offer execution, but for consistency we emit it at posthook end.

If the posthook of the offer fails. Then we emit `OfferSuccessWithPosthookData` instead of just `OfferSuccess`. This event has one extra field, which is the reason for the posthook failure. By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics.

By emitting `offerId`, `wants` and `gives`, an indexer can keep track of whether the offer was partially or fully taken, by looking at the what the offer was posted at.

### OrderComplete

This event is emitted when a market order is finished.

It only emits the total `fee paid`. We need this event, in order to know that a market order is completed. This way an indexer can know exactly in what context we are in.
The total `fee paid` for that market order, is needed, as we do not emit this any other place. It is not indexed as there is no need for RPC calls to filter on this.

### OfferRetract

This event is emitted when a user retracts his offer.

It emits the `offerlist key`, the `maker` address, `offerId` and whether or not the user chose to `deprovision` the offer.

By emitting this event an indexer knows whether or not an offer is live. And whether or not an offer is deprovisioned. This is important because we need to know this, when we try to calculate how much an offer locks in provision. See the description of `Credit` for more info.

The `maker` is not needed for an indexer to work, but is needed for RPC calls, so it is emitted and indexed for that reason. The `offerlist key` is only indexed because it is needed for RPC calls.

### OfferWrite

This event is emitted when an offer is posted on Mangrove.

It emits the `offerlist key`, the `maker` address, the `logprice`, the `gives`, the `gasprice`, `gasreq` and the offers `id`.

By emitting the `offerlist key` and `id`, an indexer will be able to keep track of each offer, because offerlist and id together create a unique id for the offer. By emitting the `maker` address, we are able to keep track of who has posted what offer. The `logprice` and `gives`, enables an indexer to know exactly how much an offer is willing to give and at what price, this could for example be used to calculate a return. The `gasprice` and `gasreq`, enables an indexer to calculate how much provision is locked by the offer, see `Credit` for more information.

The fields `offerlist key` and `maker` are indexed, so that we can filter on them when doing RPC calls.

### CleanStart

This event is emitted when a user tries to clean offers on Mangrove, using the build in clean functionality.

It emits the `offerlist key`, the `taker` address and `offersToBeCleaned`, which is the number of offers that should be cleaned. By emitting this event, an indexer can save what `offerlist` the user is trying to clean and what `taker` is being used. This way it can keep a context for the following events being emitted (Just like `OrderStart`). The `offersToBeCleaned` is emitted so that an indexer can keep track of how many offers the user tried to clean. Combining this with the amount of `OfferFail` events emitted, then an indexer can know how many offers the user actually managed to clean. This could be used for analytics.

The fields `offerlist key` and `taker` are indexed, so that we can filter on them when doing RPC calls.

### CleanComplete

This event is emitted when a Clean operation is completed.

It does not emit any fields. This event is only needed in order to know that the clean operation is completed. This way an indexer can know exactly in what context we are in. It could emit the total bounty received, but in order to know who got the bounty, an indexer would still be needed or we would have to emit the taker address aswell, in order for an RPC call to find the data. But an indexer would still be able to find this info, buy collecting all the previous events. So we do not emit the bounty.

### SetActive

This event is emitted when an offerlist is activated or deactivated. Meaning one half of a market is opened.

It emits the `offerlist key` and the boolean `value`. By emitting this, an indexer will be able to keep track of what offerlists are active.

The `offerlist key` is indexed, so that we can filter on it when doing RPC calls.

### SetDensityFixed

This event is emitted when the density of an offerlist is changed.

It emits the `offerlist key` and the `density`. By emitting this, an indexer will be able to keep track of what density each offerlist has.

The `offerlist key` is indexed, so that we can filter on it when doing RPC calls.

### SetFee

This event is emitted when the fee of an offerlist is changed.

It emits the `offerlist key` and the `fee`. By emitting this, an indexer will be able to keep track of what fee each offerlist has.

The `offerlist key` is indexed, so that we can filter on it when doing RPC calls.

### SetGasbase

This event is emitted when the gasbase of an offerlist is changed.

It emits the `offerlist key` and the `gasbase`. By emitting this, an indexer will be able to keep track of what gasbase each offerlist has.

The `offerlist key` is indexed, so that we can filter on it when doing RPC calls.

### SetGasmax

This event is emitted when the gasmax of Mangrove is set.

It emits the `gasmax`. By emitting this, an indexer will be able to keep track of what gasmax Mangrove has. Read more about Mangroves gasmax on [docs.mangrove.exchange](docs.mangrove.exchange)

No fields are indexed as there is no need for RPC calls to filter on this.

### SetGasprice

This event is emitted when the gasprice of Mangrove is set.

It emits the `gasprice`. By emitting this, an indexer will be able to keep track of what gasprice Mangrove has. Read more about Mangroves gasprice on [docs.mangrove.exchange](docs.mangrove.exchange)

No fields are indexed as there is no need for RPC calls to filter on this.

### SetGovernance

This event is emitted when the governance of Mangrove is set.

It emits the `governance` address. By emitting this, an indexer will be able to keep track of what governance address Mangrove has.

No fields are indexed as there is no need for RPC calls to filter on this.

### SetMonitor

This event is emitted when the monitor address of Mangrove is set. Be aware that the address for Monitor is also the address for the oracle.

It emits the `monitor` / `oralce` address. By emitting this, an indexer will be able to keep track of what monitor/oracle address Mangrove use.

No fields are indexed as there is no need for RPC calls to filter on this.

### SetNotify

This event is emitted when the configuration for notify on Mangrove is set.

It emits a boolean value, to tell whether or not notify is active. By emitting this, an indexer will be able to keep track of whether or not Mangrove notifies the Monitor/Oracle when and offer is taken, either successfuly or not.

No fields are indexed as there is no need for RPC calls to filter on this.

### SetUseOracle

This event is emitted when the configuration for whether to use an oracle or not is set.

It emits the `useOracle`, which is a boolean value, that controls whether or not Mangrove reads its `gasprice` and `density` from an oracle or uses its own local values. By emitting this, an indexer will be able to keep track of if Mangrove is using an oracle.

No fields are indexed as there is no need for RPC calls to filter on this.
