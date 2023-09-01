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

We should probably change it to olKey instead of outbound token and inbound token. Will save event size and the map size.

## Credit

This is emitted when a user's account on mangrove is credited with some native funds, to be used as provision for offers.

Emits the makers address and the value credited

These are the scenarios where it can happen:

- Fund mangrove directly
- When posting an offer
- When updating an offer
  - funding mangrove
  - the updated offer needs less provision, than it already has
- When retracting an offer
- When an offer fails. The remaining provision gets credited back to the maker

A challenge for an indexer is to know how much provision each offer locks in provision. With the current events, an indexer is going to have to know the liveness, gasreq and gasprice of the offer. If the offer is not live, then know if it has been deprovisioned. And know what the gasbase of the offerlist was when the offer was posted. With this information an indexer can calculate the exact provision locked by the offer.

Another information that an indexer cannot deduce, is in what scenario the credit event happened. E.g. We don't know if the credit event happened because an offer failed or if the user simply funded mangrove.

## Debit

This is emitted when a user's account on mangrove is debited with some native funds.

Emits the makers address and the value debited.

These are the scenarios where it can happen:

- Withdraw funds from mangrove directly
- When posting an offer
- When updating an offer and it requires more provision that it already has

Same challenges as for Credit

## Kill

Emitted when the mangrove instance is killed

## NewMgv

Emitted when a new mangrove is deployed.

Is this event needed?

## OrderStart

This event is emitted when a market order is started on mangrove.

It emits the offer list key, the taker, the maxLogPrice, fillVolume and fillWants.

By emitting this we can in an indexer keep track of what context the current market order is in. E.g. If a user starts a market order and one of the offers taken also starts a market order, then we can in an indexer have a stack of started market orders and thereby know exactly what offer list the order is running on and the taker.

By emitting maxLogPrice, fillVolume and fillWants, we can now also know how much of the market order was filled and if it matches the price given. See OrderComplete for more

## OfferFail

This event is emitted when an offer fails, because of a maker error.

It emits the offerId, the offers wants, gives and the reason for failure. It is emitted in the offer execution and not after the posthook of the offer. This is because we need to know the reason for failure, and that is only known at offer execution.

By emitting this event, an indexer can keep track of if an offer failed and thereby if the offer is live. By emitting the wants and gives that the offer was taken with, then an indexer can keep track of these amounts, which could be useful for e.g. strategy manager, to know if their offers fail at a certain amount.

## OfferRetract

This event is emitted when a user retracts his offer.

It emits the offer list key, the maker address, offerId and whether or not the user chose to deprovision the offer.

By emitting this event an indexer knows whether or not an offer is live. And whether or not an offer is deprovisioned. This is important because we need to know when we try to calculate how much an offer locks in provision. See the description of Credit for more info
OfferSuccess
This event is emitted when an offer is successfully taken. Meaning both maker and taker has gotten their funds.

It emits the maker address, the offerId, and the wants and gives that the offer was taken at.

By emitting the maker address and offer Id, an indexer can keep track of what offers belong to what addresses. By emitting wants and gives, an indexer can keep track of whether the offer was partially or fully taken

## OfferWrite

This event is emitted when an offer is posted on mangrove.

It emits the offer list key, the maker address, the logprice, the gives, the gasprice, gasreq and the offers id.

By emitting the offer list key and id, an indexer will be able to keep track of each offer, because offer list and id together create a unique id for the offer. By emitting the maker address, we are able to keep track of who has posted what offer. The logprice and gives, enables an indexer to know exactly how much an offer is willing to give and at what price, this could for example be used to calculate a return. The gasprice and gasreq, enables an indexer to calculate how much provision is locked by the offer, see Credit for more information.

## PosthookFail

This event is only emitted if the maker posthook fails.

It only emits the posthook data, which is the information about why the posthook failed. By emitting the posthook data, an indexer can keep track of the reason posthook fails, this could for example be used for analytics.

The difference between this event and OfferFail is that the OfferFail event is only posted if the actual offer is not executed. Where this event is emitted if the offers posthook fails.
OrderComplete
This event is emitted when a market order is finished.

It only emits the total fee

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
