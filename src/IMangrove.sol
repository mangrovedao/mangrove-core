// SPDX-License-Identifier: Unlicense
// This file must be kept up-to-date with the actual Mangrove interface.

pragma solidity >=0.7.0 <0.9.0;

import "@mgv/src/core/MgvLib.sol";

///@title Interface for the Mangrove contract.
interface IMangrove is HasMgvEvents {
  // # Permit functions

  ///@notice See {IERC20Permit-DOMAIN_SEPARATOR}.
  ///@return the domain separator.
  function DOMAIN_SEPARATOR() external view returns (bytes32);

  ///@notice See {IERC20Permit-PERMIT_TYPEHASH}.
  ///@return The permit type hash.
  function PERMIT_TYPEHASH() external pure returns (bytes32);

  ///@notice approves the spender to spend the amount of tokens on behalf of the caller.
  ///@param outbound_tkn The address of the (maker) outbound token.
  ///@param inbound_tkn The address of the (maker) inbound token.
  ///@param spender The address of the spender.
  ///@param value The amount of tokens to approve.
  ///@return true if the approval succeeded; always true.
  function approve(address outbound_tkn, address inbound_tkn, address spender, uint value) external returns (bool);

  ///@notice returns the allowance of the spender to spend tokens on behalf of the owner.
  ///@param outbound_tkn The address of the (maker) outbound token.
  ///@param inbound_tkn The address of the (maker) inbound token.
  ///@param owner The address of the owner.
  ///@param spender The address of the spender.
  ///@return amount The amount of tokens the spender is allowed to spend on behalf of the owner.
  function allowance(address outbound_tkn, address inbound_tkn, address owner, address spender)
    external
    view
    returns (uint amount);

  ///@notice Adapted from [Uniswap v2 contract](https://github.com/Uniswap/uniswap-v2-core/blob/55ae25109b7918565867e5c39f1e84b7edd19b2a/contracts/UniswapV2ERC20.sol#L81)
  ///@param outbound_tkn The address of the (maker) outbound token.
  ///@param inbound_tkn The address of the (maker) inbound token.
  ///@param owner The address of the owner.
  ///@param spender The address of the spender.
  ///@param value The amount of tokens to approve.
  ///@param deadline The deadline after which the permit is no longer valid.
  ///@param v The signature v parameter.
  ///@param r The signature r parameter.
  ///@param s The signature s parameter.
  function permit(
    address outbound_tkn,
    address inbound_tkn,
    address owner,
    address spender,
    uint value,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external;

  ///@notice See {IERC20Permit-nonces}.
  ///@param owner The address of the owner.
  ///@return nonce The current nonce of the owner.
  function nonces(address owner) external view returns (uint nonce);

  // # Taker functions

  ///@notice Performs a market order on a specified offer list taking offers up to a limit price.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param maxTick Must be `>= MIN_TICK` and `<= MAX_TICK`. The log of limit price the taker is ready to pay (meaning: the log base 1.0001 of the ratio of inbound tokens over outbound tokens)
  ///@param fillVolume Must be `<= MAX_SAFE_VOLUME`. If `fillWants` is true, the amount of `olKey.outbound_tkn` the taker wants to buy; otherwise, the amount of `olKey.inbound_tkn` the taker wants to sell.
  ///@param fillWants if true, the matching engine tries to get the taker all they want; otherwise, the matching engine tries to sell all that the taker gives. In both cases subject to the price limit.
  ///@return takerGot The amount of `olKey.outbound_tkn` the taker got.
  ///@return takerGave The amount of `olKey.inbound_tkn` the taker gave.
  ///@return bounty The amount of native token the taker got as a bounty due to failing offers (in wei)
  ///@return feePaid The amount of `olKey.outbound_tkn` the taker paid as a fee to Mangrove.
  ///@dev The market order stops when there are no more offers at or below `maxTick`, when the end of the book has been reached, or:
  ///@dev - If `fillWants` is true, the market order stops when `fillVolume` units of `olKey.outbound_tkn` have been obtained. To buy a specific volume of `olKey.outbound_tkn` at any price, set `fillWants` to true, set `fillVolume` to the volume you want to buy, and set `maxTick` to the `MAX_TICK` constant.
  ///@dev - If `fillWants` is false, the market order stops when `fillVolume` units of `olKey.inbound_tkn` have been paid. To sell a specific volume of `olKey.inbound_tkn` at any price, set `fillWants` to false, set `fillVolume` to the volume you want to sell, and set `maxTick` to the `MAX_TICK` constant.
  function marketOrderByTick(OLKey memory olKey, Tick maxTick, uint fillVolume, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  ///@notice Performs a market order on a specified offer list taking offers up to a limit price, while allowing to specify a custom `maxGasreqForFailingOffers`.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param maxTick Must be `>= MIN_TICK` and `<= MAX_TICK`. The log of the limit price the taker is ready to pay (meaning: the log base 1.0001 of the ratio of inbound tokens over outbound tokens).
  ///@param fillVolume Must be `<= MAX_SAFE_VOLUME`. If `fillWants` is true, the amount of `olKey.outbound_tkn` the taker wants to buy; otherwise, the amount of `olKey.inbound_tkn` the taker wants to sell.
  ///@param fillWants if true, the matching engine tries to get the taker all they want; otherwise, the matching engine tries to sell all that the taker gives. In both cases subject to the price limit.
  ///@param maxGasreqForFailingOffers The maximum allowed gas required for failing offers (in wei).
  ///@return takerGot The amount of `olKey.outbound_tkn` the taker got.
  ///@return takerGave The amount of `olKey.inbound_tkn` the taker gave.
  ///@return bounty The amount of native token the taker got as a bounty due to failing offers (in wei)
  ///@return feePaid The amount of `olKey.outbound_tkn` the taker paid as a fee to Mangrove.
  ///@dev Mangrove stops a market order after it has gone through failing offers such that their cumulative `gasreq` is greater than the global `maxGasreqForFailingOffers` parameter. This function can be used by the taker to override the default `maxGasreqForFailingOffers` parameter.
  function marketOrderByTickCustom(
    OLKey memory olKey,
    Tick maxTick,
    uint fillVolume,
    bool fillWants,
    uint maxGasreqForFailingOffers
  ) external returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  ///@notice Performs a market order on a specified offer list taking offers up to a limit price defined by a ratio `inbound_tkn/outbound_tkn` of volumes.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param takerWants Must be `<= MAX_SAFE_VOLUME`. The amount the taker wants. This is used along with `takerGives` to derive a max price (`maxTick`) which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param takerGives Must be `<= MAX_SAFE_VOLUME`. The amount the taker gives. This is used along with `takerWants` to derive a max price (`maxTick`) which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param fillWants if true, the matching engine tries to get the taker all they want; otherwise, the matching engine tries to sell all that the taker gives. In both cases subject to the price limit.
  ///@return takerGot The amount of `olKey.outbound_tkn` the taker got.
  ///@return takerGave The amount of `olKey.inbound_tkn` the taker gave.
  ///@return bounty The amount of native token the taker got as a bounty due to failing offers (in wei)
  ///@return feePaid The amount of `olKey.outbound_tkn` the taker paid as a fee to Mangrove.
  ///@dev This function is just a wrapper for `marketOrderByTick`, see that function for details.
  ///@dev When deriving the tick, then `takerWants = 0` has a special meaning and the tick for the highest possible ratio between wants and gives will be used,
  ///@dev and if `takerGives = 0` and `takerWants != 0`, then the tick for the lowest possible ratio will be used.
  function marketOrderByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  ///@notice Performs a market order on a specified offer list taking offers up to a limit price for a specified taker.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param maxTick Must be `>= MIN_TICK` and `<= MAX_TICK`. The log of the limit price the taker is ready to pay (meaning: the log base 1.0001 of the ratio of inbound tokens over outbound tokens).
  ///@param fillVolume Must be `<= MAX_SAFE_VOLUME`. If `fillWants` is true, the amount of `olKey.outbound_tkn` the taker wants to buy; otherwise, the amount of `olKey.inbound_tkn` the taker wants to sell.
  ///@param fillWants if true, the matching engine tries to get the taker all they want; otherwise, the matching engine tries to sell all that the taker gives. In both cases subject to the price limit.
  ///@param taker The taker from which amounts will be transferred from and to. If the `msg.sender`'s allowance for the given `olKey.outbound_tkn`,`olKey.inbound_tkn` is strictly less than the total amount eventually spent by `taker`, the call will fail.
  ///@return takerGot The amount of `olKey.outbound_tkn` the taker got.
  ///@return takerGave The amount of `olKey.inbound_tkn` the taker gave.
  ///@return bounty The amount of native token the taker got as a bounty due to failing offers (in wei)
  ///@return feePaid The amount of `olKey.outbound_tkn` the taker paid as a fee to Mangrove.
  ///@dev The `bounty` will be send to `msg.sender` but transfers will be for `taker`. Requires prior permission.
  ///@dev See also `marketOrderByTick`.
  function marketOrderForByTick(OLKey memory olKey, Tick maxTick, uint fillVolume, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  ///@notice Performs a market order on a specified offer list taking offers up to a limit price defined by a ratio `inbound_tkn/outbound_tkn` of volumes for a specified taker.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param takerWants Must be `<= MAX_SAFE_VOLUME`. The amount the taker wants. This is used along with `takerGives` to derive a max price (`maxTick`) which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param takerGives Must be `<= MAX_SAFE_VOLUME`. The amount the taker gives. This is used along with `takerGives` to derive a max price (`maxTick`) which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param fillWants if true, the matching engine tries to get the taker all they want; otherwise, the matching engine tries to sell all that the taker gives. In both cases subject to the price limit.
  ///@param taker The taker from which amounts will be transferred from and to the. If the `msg.sender`'s allowance for the given `olKey.outbound_tkn`,`olKey.inbound_tkn` are strictly less than the total amount eventually spent by `taker`, the call will fail.
  ///@return takerGot The amount of `olKey.outbound_tkn` the taker got.
  ///@return takerGave The amount of `olKey.inbound_tkn` the taker gave.
  ///@return bounty The amount of native token the taker got as a bounty due to failing offers (in wei)
  ///@return feePaid The amount of native token the taker paid as a fee (in wei of `olKey.outbound_tkn`)
  ///@dev The `bounty` will be send to `msg.sender` but transfers will be for `taker`. Requires prior permission.
  ///@dev See also `marketOrderByVolume`.
  function marketOrderForByVolume(OLKey memory olKey, uint takerWants, uint takerGives, bool fillWants, address taker)
    external
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid);

  // # Cleaning functions

  /* # Cleaning */
  ///@notice Cleans multiple offers, i.e. executes them and remove them from the book if they fail, transferring the failure penalty as bounty to the caller.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param targets The offers to clean, identified by their (`offerId, tick, gasreq, takerWants`) that will make them fail.
  ///@param taker The taker used for transfers (should be able to deliver token amounts).
  ///@return successes The number of successfully cleaned offers.
  ///@return bounty The total bounty received by the caller.
  ///@dev If an offer succeeds, the execution of that offer is reverted, it stays in the book, and no bounty is paid; The `cleanByImpersonation` function itself will not revert.
  ///@dev Note that Mangrove won't attempt to execute an offer if the values in a target don't match its offer. To distinguish between a non-executed clean and a fail clean (due to the offer itself not failing), you must inspect the log (see `MgvLib.sol`) or check the received bounty.
  ///@dev Any `taker` can be impersonated when cleaning because:
  ///@dev - The function reverts if the offer succeeds, reverting any token transfers.
  ///@dev - After a `clean` where the offer has failed, all ERC20 token transfers have also been reverted -- but the sender will still have received the bounty of the failing offers. */
  function cleanByImpersonation(OLKey memory olKey, MgvLib.CleanTarget[] calldata targets, address taker)
    external
    returns (uint successes, uint bounty);

  // # Maker functions

  ///@notice Adds funds to Mangrove for the caller (the maker) to use for provisioning offers.
  function fund() external payable;

  ///@notice Adds funds to Mangrove for the caller (the maker) to use for provisioning offers.
  receive() external payable;

  ///@notice Adds funds to Mangrove for the maker to use for provisioning offers.
  ///@param maker The maker to add funds for.
  function fund(address maker) external payable;

  ///@notice Withdraws the caller's (the maker's) free native tokens (funds for provisioning offers not locked by an offer) by transferring them to the caller.
  ///@param amount the amount to withdraw.
  ///@return noRevert whether the transfer succeeded.
  function withdraw(uint amount) external returns (bool noRevert);

  ///@notice Gets the maker's free balance of native tokens (funds for provisioning offers not locked by an offer).
  ///@param maker The maker to get the balance for.
  ///@return balance The maker's free balance of native tokens (funds for provisioning offers not locked by an offer).
  function balanceOf(address maker) external view returns (uint balance);

  ///@notice Creates a new offer on Mangrove, where the caller is the maker. The maker can implement the `IMaker` interface to be called during offer execution.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param tick Must be `>= MIN_TICK` and `<= MAX_TICK`. The tick (which is a power of 1.0001 and induces a price). The actual tick of the offer will be the smallest tick offerTick > tick that satisfies offerTick % tickSpacing == 0.
  ///@param gives Must be `<= MAX_SAFE_VOLUME`. The amount of `olKey.outbound_tkn` the maker gives.
  ///@param gasreq The amount of gas required to execute the offer logic in the maker's `IMaker` implementation. This will limit the gas available, and the offer will fail if it spends more.
  ///@param gasprice The maximum gas price the maker is willing to pay a penalty for due to failing execution.
  ///@return offerId the id of the offer on Mangrove. Can be used to retract or update the offer (even to reuse a taken offer).
  ///@dev The gasreq and gasprice are used to derive the provision which will be used to pay a penalty if the offer fails.
  ///@dev This function is payable to enable delivery of the provision along with the offer creation.
  function newOfferByTick(OLKey memory olKey, Tick tick, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  ///@notice Creates a new offer on Mangrove, where the caller is the maker. The maker can implement the `IMaker` interface to be called during offer execution.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param wants Must be less than MAX_SAFE_VOLUME. The amount of `olKey.inbound_tkn` the maker wants. This is used along with `gives` to derive a tick (price). which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param gives Must be less than MAX_SAFE_VOLUME. The amount of `olKey.outbound_tkn` the maker gives. This is used along with `wants` to derive a tick (price). which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`. Must be less than MAX_SAFE_VOLUME.
  ///@param gasreq The amount of gas required to execute the offer logic in the maker's `IMaker` implementation. This will limit the gas available, and the offer will fail if it spends more.
  ///@param gasprice The maximum gas price the maker is willing to pay a penalty for due to failing execution.
  ///@return offerId the id of the offer on Mangrove. Can be used to retract or update the offer (even to reuse a taken offer).
  ///@dev This function is just a wrapper for `newOfferByTick`, see that function for details.
  function newOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice)
    external
    payable
    returns (uint offerId);

  ///@notice Updates an existing offer on Mangrove, where the caller is the maker.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param tick Must be `>= MIN_TICK` and `<= MAX_TICK`. The tick (which is a power of 1.0001 and induces a price).
  ///@param gives The amount of `olKey.outbound_tkn` the maker gives. Must be less than MAX_SAFE_VOLUME.
  ///@param gasreq The amount of gas required to execute the offer logic in the maker's `IMaker` implementation.
  ///@param gasprice The maximum gas price the maker is willing to pay a penalty for due to failing execution.
  ///@param offerId The id of the offer on Mangrove.
  ///@dev See `newOfferByTick` for additional details.
  function updateOfferByTick(OLKey memory olKey, Tick tick, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  ///@notice Updates an existing, owned offer on Mangrove, where the caller is the maker.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param wants The amount of `olKey.inbound_tkn` the maker wants. This is used along with `gives` to derive a tick (price). which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`.
  ///@param gives The amount of `olKey.outbound_tkn` the maker gives. This is used along with `wants` to derive a tick (price). which is the lowest allowed tick in the offer list such that `log_1.0001(takerGives/takerWants) <= maxTick`. Must be less than MAX_SAFE_VOLUME.
  ///@param gasreq The amount of gas required to execute the offer logic in the maker's `IMaker` implementation.
  ///@param gasprice The maximum gas price the maker is willing to pay a penalty for due to failing execution.
  ///@param offerId The id of the offer on Mangrove.
  ///@dev This function is just a wrapper for `updateOfferByTick`, see that function for details.
  function updateOfferByVolume(OLKey memory olKey, uint wants, uint gives, uint gasreq, uint gasprice, uint offerId)
    external
    payable;

  ///@notice Retracts an offer from Mangrove, where the caller is the maker.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param offerId The id of the offer on Mangrove.
  ///@param deprovision Whether to deprovision the offer, i.e, return the provision to the maker's balance on Mangrove.
  ///@return provision The amount of native token deprovisioned for the offer (in wei).
  ///@dev `withdraw` can be used to withdraw the funds after deprovisioning.
  ///@dev Leaving funds provisioned can be used to save gas if offer is later updated.
  function retractOffer(OLKey memory olKey, uint offerId, bool deprovision) external returns (uint provision);

  // # Global config view functions

  ///@notice Gets the global configuration for Mangrove.
  ///@return _global The global configuration for Mangrove.
  function global() external view returns (Global _global);

  // # Offer list view functions

  ///@notice Gets the local configuration for a specific offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@return _local The local configuration for the offer list.
  function local(OLKey memory olKey) external view returns (Local _local);

  ///@notice Gets the global configuration for Mangrove and local the configuration for a specific offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@return _global The global configuration for Mangrove.
  ///@return _local The local configuration for the offer list.
  function config(OLKey memory olKey) external view returns (Global _global, Local _local);

  ///@notice Determines whether the reentrancy lock is in effect for the offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@return true if locked; otherwise, false.
  ///@dev The lock protects modifying or inspecting the offer list while an order is in progress.
  function locked(OLKey memory olKey) external view returns (bool);

  ///@notice Gets the `offerId` of the best offer in the offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@return offerId The `offerId` of the best offer on the offer list.
  function best(OLKey memory olKey) external view returns (uint offerId);

  ///@notice Gets the offer list key with the given hash (if the offer list key has been activated at least once).
  ///@param olKeyHash the hash of the offer list key.
  ///@return olKey the olKey.
  function olKeys(bytes32 olKeyHash) external view returns (OLKey memory olKey);

  // # Offer view functions

  ///@notice Gets an offer in packed format.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param offerId The `offerId` of the offer on the offer list.
  ///@return offer The offer in packed format.
  function offers(OLKey memory olKey, uint offerId) external view returns (Offer offer);

  ///@notice Gets an offer's details in packed format.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param offerId The `offerId` of the offer on the offer list.
  ///@return offerDetail The offer details in packed format.
  function offerDetails(OLKey memory olKey, uint offerId) external view returns (OfferDetail offerDetail);

  ///@notice Gets both an offer and its details in packed format.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param offerId The `offerId` of the offer on the offer list.
  ///@return offer The offer in packed format.
  ///@return offerDetail The offer details in packed format.
  function offerData(OLKey memory olKey, uint offerId) external view returns (Offer offer, OfferDetail offerDetail);

  // # Governance functions

  ///@notice Gets the governance address.
  ///@return the governance address.
  function governance() external view returns (address);

  ///@notice Activates an offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param fee in basis points, of `olKey.outbound_tkn` given to the taker. This fee is sent to Mangrove. Fee is capped to ~2.5%.
  ///@param density96X32 The density of the offer list used to define a minimum offer volume. See `setDensity96X32`.
  ///@param offer_gasbase The gasbase of the offer list used to define a minimum provision necessary for offers. See `setGasbase`.
  ///@dev If the flipped offer list is active then the offer lists are expected to have the same `tickSpacing`.
  function activate(OLKey memory olKey, uint fee, uint density96X32, uint offer_gasbase) external;

  ///@notice Deactivates an offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  function deactivate(OLKey memory olKey) external;

  ///@notice Kills the Mangrove instance. A dead instance cannot have offers executed or funds received, but offers can be retracted and funds can be withdrawn.
  function kill() external;

  ///@notice Sets the density.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param density96X32 is given as a 96.32 fixed point number. It will be stored as a 9-bit float and be approximated towards 0. The maximum error is 20%. See `DensityLib` for more information.
  ///@dev Useless if `global.useOracle != 0` and oracle returns a valid density.
  function setDensity96X32(OLKey memory olKey, uint density96X32) external;

  ///@notice Sets the fee for the offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param fee in basis points, of `olKey.outbound_tkn` given to the taker. This fee is sent to Mangrove. Fee is capped to ~2.5%.
  function setFee(OLKey memory olKey, uint fee) external;

  ///@notice Sets the gasbase for the offer list.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param offer_gasbase The gasbase of the offer list used to define a minimum provision necessary for offers. Represents the gas overhead used by processing the offer inside Mangrove + the overhead of initiating an entire order. Stored in thousands in a maximum of 9 bits.
  function setGasbase(OLKey memory olKey, uint offer_gasbase) external;

  ///@notice Sets the gasmax for Mangrove, the maximum amount of gas an offer can require to execute.
  ///@param gasmax The maximum amount of gas required to execute an offer. Must fit in 24 bits.
  function setGasmax(uint gasmax) external;

  ///@notice Sets the maximum number of times a market order can recursively execute offers. This is a protection against stack overflows.
  ///@param maxRecursionDepth The maximum number of times a market order can recursively execute offers.
  function setMaxRecursionDepth(uint maxRecursionDepth) external;

  ///@notice Sets the maximum cumulative `gasreq` for failing offers during a market order before doing a partial fill.
  ///@param maxGasreqForFailingOffers The maximum cumulative `gasreq` for failing offers during a market order before doing a partial fill. 32 bits.
  function setMaxGasreqForFailingOffers(uint maxGasreqForFailingOffers) external;

  ///@notice Sets the gasprice (in Mwei, 26 bits)
  ///@param gasprice The gasprice (in Mwei, 26 bits)
  function setGasprice(uint gasprice) external;

  ///@notice Sets a new governance address.
  ///@param governanceAddress The new governance address.
  function setGovernance(address governanceAddress) external;

  ///@notice Sets the monitor/oracle. The `monitor/oracle` can provide real-time values for `gasprice` and `density` to Mangrove. It can also receive liquidity event notifications.
  ///@param monitor The new monitor/oracle address.
  function setMonitor(address monitor) external;

  ///@notice Sets whether Mangrove notifies the Monitor when and offer is taken
  ///@param notify Whether Mangrove notifies the Monitor when and offer is taken
  function setNotify(bool notify) external;

  ///@notice Sets whether Mangrove uses the monitor as oracle for `gasprice` and `density` values.
  ///@param useOracle Whether Mangrove uses the monitor as oracle for `gasprice` and `density` values.
  function setUseOracle(bool useOracle) external;

  ///@notice Transfer ERC20 tokens to governance.
  ///@param tokenAddress The address of the ERC20 token.
  ///@param value The amount of tokens to transfer.
  function withdrawERC20(address tokenAddress, uint value) external;

  // # Tick tree view functions

  ///@notice Gets a leaf
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param index The index.
  ///@return the leaf.
  function leafs(OLKey memory olKey, int index) external view returns (Leaf);

  ///@notice Gets a level 3 field
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param index The index.
  ///@return the field
  function level3s(OLKey memory olKey, int index) external view returns (Field);

  ///@notice Gets a level 2 field
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param index The index.
  ///@return the field
  function level2s(OLKey memory olKey, int index) external view returns (Field);

  ///@notice Gets a level 1 field
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@param index The index.
  ///@return the field
  function level1s(OLKey memory olKey, int index) external view returns (Field);

  ///@notice Gets the root from local.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`.
  ///@return the root
  function root(OLKey memory olKey) external view returns (Field);

  // # Internal functions

  ///@notice internal function used to flashloan tokens from taker to maker, for maker to source the promised liquidity.
  ///@param sor data about an order-offer match.
  ///@param taker the taker.
  ///@return gasused the amount of gas used for `makerExecute`.
  ///@return makerData the data returned by `makerExecute`.
  ///@dev not to be called externally - only external to be able to revert.
  function flashloan(MgvLib.SingleOrder memory sor, address taker) external returns (uint gasused, bytes32 makerData);

  ///@notice internal function used to clean failing offers.
  ///@param olKey The offer list key given by (maker) `outbound_tkn`, (maker) `inbound_tkn`, and `tickSpacing`
  ///@param offerId The id of the offer on Mangrove.
  ///@param tick Must be `>= MIN_TICK` and `<= MAX_TICK`. The tick.
  ///@param gasreq The gas required for the offer.
  ///@param takerWants Must be `<= MAX_SAFE_VOLUME`. The amount of `olKey.outbound_tkn` the taker wants.
  ///@param taker The taker used for transfers (should be able to deliver token amounts).
  ///@return bounty the bounty paid.
  ///@dev not to be called externally - only external to be able to revert.
  function internalCleanByImpersonation(
    OLKey memory olKey,
    uint offerId,
    Tick tick,
    uint gasreq,
    uint takerWants,
    address taker
  ) external returns (uint bounty);

  ///@notice Fall back function (forwards calls to `MgvAppendix`)
  ///@param callData The call data.
  ///@return the result.
  fallback(bytes calldata callData) external returns (bytes memory);
}
