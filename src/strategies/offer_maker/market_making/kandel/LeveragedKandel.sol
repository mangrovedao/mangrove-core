// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePrivateRouter} from "mgv_src/strategies/routers/integrations/AavePrivateRouter.sol";
import {IATokenIsh} from "mgv_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract LeveragedKandel is GeometricKandel {
  ///@notice Indication that this is first puller (returned from __lastLook__) so posthook should deposit liquidity on AAVE
  bytes32 internal constant IS_FIRST_PULLER = "IS_FIRST_PULLER";

  ///@notice Constructor
  ///@param mgv The Mangrove deployment.
  ///@param base Address of the base token of the market Kandel will act on
  ///@param quote Address of the quote token of the market Kandel will act on
  ///@param gasreq the gasreq to use for offers
  ///@param gasprice the gasprice to use for offers
  ///@param reserveId identifier of this contract's reserve when using a router.
  constructor(IMangrove mgv, IERC20 base, IERC20 quote, uint gasreq, uint gasprice, address reserveId)
    GeometricKandel(mgv, base, quote, gasreq, gasprice, reserveId)
  {
    // one makes sure it is not possible to deploy an AAVE kandel on aTokens
    // allowing Kandel to deposit aUSDC for instance would conflict with other Kandel instances bound to the same router
    // and trading on USDC.
    // The code below verifies that neither base nor quote are official AAVE overlyings.
    bool isOverlying;
    try IATokenIsh(address(base)).UNDERLYING_ASSET_ADDRESS() returns (address) {
      isOverlying = true;
    } catch {}
    try IATokenIsh(address(quote)).UNDERLYING_ASSET_ADDRESS() returns (address) {
      isOverlying = true;
    } catch {}
    require(!isOverlying, "LeveragedKandel/cannotTradeAToken");
  }

  ///@notice returns the router as an Aave router
  function privateRouter() private view returns (AavePrivateRouter) {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "LeveragedKandel/uninitialized");
    return AavePrivateRouter(address(router_));
  }

  ///@notice Sets the AaveRouter as router and activates router for base and quote
  ///@param router_ the Aave router to use.
  function initialize(AavePrivateRouter router_) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`. We call __activate__ instead of activate just to save gas.
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(offerGasreq());
  }

  ///@notice publishes bids/asks for the distribution in the `indices`. Caller should follow the desired distribution in `baseDist` and `quoteDist`.
  ///@param distribution the distribution of base and quote for Kandel indices
  ///@param pivotIds the pivot to be used for the offer
  ///@param firstAskIndex the (inclusive) index after which offer should be an ask.
  ///@param parameters the parameters for Kandel. Only changed parameters will cause updates. Set `gasreq` and `gasprice` to 0 to keep existing values.
  ///@param token collateral type
  ///@param amount amount of collateral to deposit
  ///@dev This function is used at initialization and can fund with provision for the offers.
  ///@dev Use `populateChunk` to split up initialization or re-initialization with same parameters, as this function will emit.
  ///@dev If this function is invoked with different ratio, pricePoints, spread, then first retract all offers.
  ///@dev msg.value must be enough to provision all posted offers (for chunked initialization only one call needs to send native tokens).
  function populate(
    Distribution calldata distribution,
    uint[] calldata pivotIds,
    uint firstAskIndex,
    Params calldata parameters,
    IERC20 token,
    uint amount
  ) external payable onlyAdmin {
    _deposit(token, amount);
    setParams(parameters);
    MGV.fund{value: msg.value}();
    _populateChunk(distribution, pivotIds, firstAskIndex, params.gasreq, params.gasprice);
  }

  function depositFunds(IERC20 token, uint amount) external onlyAdmin {
    _deposit(token, amount);
    privateRouter().pushAndSupply(token, amount, IERC20(address(0)), 0);
  }

  function withdrawFunds(IERC20 token, uint amount, address recipient) external onlyAdmin {
    if (amount != 0) {
      router().pull(token, RESERVE_ID, amount, true);
    }
    _withdraw(token, amount, recipient);
  }

  ///@notice returns the amount of the router's balance that belong to this contract for the token offered for the offer type.
  ///@inheritdoc AbstractKandel
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return router().balanceOfReserve(token, RESERVE_ID) + super.reserveBalance(ba);
  }

  /// @notice Verifies, prior to pulling funds from the router, whether pull will be fetching funds on AAVE
  /// @inheritdoc MangroveOffer
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32) {
    bytes32 makerData = super.__lastLook__(order);
    return (IERC20(order.outbound_tkn).balanceOf(address(router())) < order.wants) ? IS_FIRST_PULLER : makerData;
  }

  ///@notice overrides and replaces Direct's posthook in order to push and supply on AAVE with a single call when offer logic is the first to pull funds from AAVE
  ///@inheritdoc MangroveOffer
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32 repostStatus)
  {
    // handle dual offer posting
    transportSuccessfulOrder(order);

    // handles pushing back liquidity to the router
    if (makerData == IS_FIRST_PULLER) {
      // if first puller, then router should deposit liquidity on AAVE
      privateRouter().pushAndSupply(BASE, BASE.balanceOf(address(this)), QUOTE, QUOTE.balanceOf(address(this)));
      // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // reposting offer residual if any - call super to let flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
  }
}
