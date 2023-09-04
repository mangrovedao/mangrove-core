# Events

Events in solidity is a hard thing to do in a optimal way. If you look at it as a purely gas efficient issue, you want to emit as few events as possible and with as few fields as possible. But as events also has to be usable for off chain user, then doing this is not always the best solution.

We tried to list the main points that we would like to do with events.

1. Use as little gas as possible
2. An indexer should be able to keep track of all offers and mangrove.
3. Doing RPC calls directly, should be able to find offers based on offer list, maker, taker, offer id, etc.

These 3 points all have there own direction and it is therefore not possible to find a solution that is optimal for all 3 points.
We have therefore tried to find a solution that is a good balance between the all 3 points.

Approach: First try and make events as minimal as possible, then add fields that are needed for an indexer and lastly add fields that are needed for RPC calls.

## Approval

This is emitted when a user permits another address to use a certain amount of its funds to do market orders, or when a user revokes another address to use a certain amount of its funds.

Approvals are offerlist based.

We emit outbound token, inbound token, owner, msg.sender, value.

Outbound, inbound and owner is indexed, this way one can filter on these fields when doing RPC calls. If we could somehow combine outbound and inbound into one field, then we could also index the spender.

As offerlist key is created from outbound, inbound and tickScale, then we probably do not want to base Approvals on offerlist key. If we ever open to markets on the same pair, but with different tickScale, then we probably want the approval to work on both markets?. This is something we need to think about.

## Credit

This is emitted when a user's account on mangrove is credited with some native funds, to be used as provision for offers.

Emits the makers address and the value credited

The maker address is indexed so that we can filter on it when doing RPC calls.

These are the scenarios where it can happen:

- Fund mangrove directly
- When posting an offer
- When updating an offer
  - funding mangrove
  - the updated offer needs less provision, than it already has
- When retracting an offer and deprovisioning it
- When an offer fails. The remaining provision gets credited back to the maker

A challenge for an indexer is to know how much provision each offer locks in provision. With the current events, an indexer is going to have to know the liveness, gasreq and gasprice of the offer. If the offer is not live, then also know if it has been deprovisioned. And know what the gasbase of the offerlist was when the offer was posted. With this information an indexer can calculate the exact provision locked by the offer.

Another information that an indexer cannot deduce, is in what scenario the credit event happened. E.g. We don't know if the credit event happened because an offer failed or if the user simply funded mangrove.

## Debit

This is emitted when a user's account on mangrove is debited with some native funds.

Emits the makers address and the value debited.

The maker address is indexed so that we can filter on it when doing RPC calls.

These are the scenarios where it can happen:

- Withdraw funds from mangrove directly
- When posting an offer
- When updating an offer and it requires more provision that it already has

Same challenges as for Credit

## Kill

Emitted when the mangrove instance is killed

Is this event needed?

## NewMgv

Emitted when a new mangrove is deployed.

Is this event needed?

## OrderStart

This event is emitted when a market order is started on mangrove.

It emits the offer list key, the taker, the maxLogPrice, fillVolume and fillWants.

The fields offer list key and taker are indexed, so that we can filter on them when doing RPC calls.

By emitting this we can in an indexer keep track of what context the current market order is in. E.g. If a user starts a market order and one of the offers taken also starts a market order, then we can in an indexer have a stack of started market orders and thereby know exactly what offer list the order is running on and the taker.

By emitting maxLogPrice, fillVolume and fillWants, we can now also know how much of the market order was filled and if it matches the price given. See OrderComplete for more

## OfferFail

This event is emitted when an offer fails, because of a maker error.

It emits offer list key, taker, maker, the offerId, the offers wants, gives, penalty and the reason for failure. Offer list key, taker and maker are all fields that we do not need, in order for an indexer to work, as an indexer will be able the get that info from former OrderStart and OrderWrite events. But in order for RPC call to filter on this, we need to emit them. Those 3 fields are indexed for the same reason.

This event is emitted doring posthook end, we wait to emit this event to the end, because we need the information of penalty, which is only available at the end of the posthook. This means that OfferFail events are emitted in reverse order, compared to what order they are taken. This is do to the way we handle posthooks. The same goes for OfferSuccess.

By emitting this event, an indexer can keep track of, if an offer failed and thereby if the offer is live. By emitting the wants and gives that the offer was taken with, then an indexer can keep track of these amounts, which could be useful for e.g. strategy manager, to know if their offers fail at a certain amount.

## OfferSuccess

This event is emitted when an offer is successfully taken. Meaning both maker and taker has gotten their funds.

It emits the offer list key, taker address, maker address, the offerId, and the wants and gives that the offer was taken at. Just as for OfferFail, the offer list key, taker and maker are not needed for an indexer to work, but are needed for RPC calls. So they are emitted and indexed for that reason. Just like OfferFail this event is emitted during posthook end, so it is emitted in reverse order compared to what order they are taken. This event could be emitted at offer execution, but for consistency we emit it at posthook end.

By emitting offerId, wants and gives, an indexer can keep track of whether the offer was partially or fully taken, by looking at the what the offer was posted at.

## PosthookFail

This event is only emitted if the maker posthook fails.

It emits the offer list key, offer id and the posthook data, which is the information about why the posthook failed. By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics. The offer list key and offer id are not needed for an indexer to work, but are needed for RPC calls, so they are emitted and indexed for that reason.

The difference between this event and OfferFail is that the OfferFail event is only posted if the actual offer is not executed. Where this event is emitted if the offers posthook fails.

## OrderComplete

This event is emitted when a market order is finished.

It only emits the total fee paid. We need this event, in order to know that a market order is completed. This way an indexer can know exactuly in what context we are in.
The total fee paid for that market order, is needed, as we do not emit this any other place. It is not indexed as there is no need for RPC calls to filter on this.

## OfferRetract

---

This event is emitted when a user retracts his offer.

It emits the offer list key, the maker address, offerId and whether or not the user chose to deprovision the offer.

By emitting this event an indexer knows whether or not an offer is live. And whether or not an offer is deprovisioned. This is important because we need to know when we try to calculate how much an offer locks in provision. See the description of Credit for more info

## OfferWrite

This event is emitted when an offer is posted on mangrove.

It emits the offer list key, the maker address, the logprice, the gives, the gasprice, gasreq and the offers id.

By emitting the offer list key and id, an indexer will be able to keep track of each offer, because offer list and id together create a unique id for the offer. By emitting the maker address, we are able to keep track of who has posted what offer. The logprice and gives, enables an indexer to know exactly how much an offer is willing to give and at what price, this could for example be used to calculate a return. The gasprice and gasreq, enables an indexer to calculate how much provision is locked by the offer, see Credit for more information.

## CleanStart

## CleanOffer

## SetActive

## SetDensity

## SetFee

## SetGasbase

## SetGasmax

## SetGasprice

## SetGovernance

## SetMonitor

## SetNotify

## SetUseOracle
