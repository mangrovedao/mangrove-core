// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {AbstractRouter, AavePooledRouter} from "mgv_src/strategies/routers/integrations/AavePooledRouter.sol";
import {IATokenIsh} from "mgv_src/strategies/vendor/aave/v3/IATokenIsh.sol";
import {GeometricKandel} from "./abstract/GeometricKandel.sol";
import {AbstractKandel} from "./abstract/AbstractKandel.sol";
import {OfferType} from "./abstract/TradesBaseQuotePair.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

///@title A Kandel strat with geometric price progression which stores funds on AAVE to generate yield.
contract AaveKandel is GeometricKandel {
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
    require(!isOverlying, "AaveKandel/cannotTradeAToken");
  }

  ///@notice returns the router as an Aave router
  ///@return The aave router.
  function pooledRouter() private view returns (AavePooledRouter) {
    AbstractRouter router_ = router();
    require(router_ != NO_ROUTER, "AaveKandel/uninitialized");
    return AavePooledRouter(address(router_));
  }

  ///@notice Sets the AaveRouter as router and activates router for base and quote
  ///@param router_ the Aave router to use.
  function initialize(AavePooledRouter router_) external onlyAdmin {
    setRouter(router_);
    // calls below will fail if router's admin has not bound router to `this`. We call __activate__ instead of activate just to save gas.
    __activate__(BASE);
    __activate__(QUOTE);
    setGasreq(offerGasreq());
  }

  ///@inheritdoc AbstractKandel
  function depositFunds(uint baseAmount, uint quoteAmount) public override {
    // transfer funds from caller to this
    super.depositFunds(baseAmount, quoteAmount);
    // push funds on the router (and supply on AAVE)
    pooledRouter().pushAndSupply(BASE, baseAmount, QUOTE, quoteAmount, RESERVE_ID);
  }

  ///@inheritdoc AbstractKandel
  ///@notice tries to withdraw funds on this contract's balance and then reaches out to the router available funds for the remainder
  function withdrawFunds(uint baseAmount, uint quoteAmount, address recipient) public override onlyAdmin {
    uint localBase = BASE.balanceOf(address(this));
    uint localQuote = QUOTE.balanceOf(address(this));

    // if amount is `type(uint).max` tell the router to withdraw all it can (i.e. pass `type(uint).max` to the router)
    // else withdraw only if there is not enough funds on this contract to match amount
    uint baseAmount_ = baseAmount == type(uint).max ? baseAmount : localBase > baseAmount ? 0 : baseAmount - localBase;
    uint quoteAmount_ =
      quoteAmount == type(uint).max ? quoteAmount : localQuote > quoteAmount ? 0 : quoteAmount - localQuote;

    if (baseAmount_ > 0) {
      pooledRouter().withdraw(BASE, RESERVE_ID, baseAmount_);
    }
    if (quoteAmount_ > 0) {
      pooledRouter().withdraw(QUOTE, RESERVE_ID, quoteAmount_);
    }
    super.withdrawFunds(baseAmount, quoteAmount, recipient);
  }

  ///@notice returns the amount of the router's that can be used by this contract, as well as local balance for the token offered for the offer type.
  ///@inheritdoc AbstractKandel
  function reserveBalance(OfferType ba) public view override returns (uint balance) {
    IERC20 token = outboundOfOfferType(ba);
    return pooledRouter().balanceOfReserve(token, RESERVE_ID) + super.reserveBalance(ba);
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
      pooledRouter().pushAndSupply(
        BASE, BASE.balanceOf(address(this)), QUOTE, QUOTE.balanceOf(address(this)), RESERVE_ID
      );
      // reposting offer residual if any - but do not call super, since Direct will flush tokens unnecessarily
      repostStatus = MangroveOffer.__posthookSuccess__(order, makerData);
    } else {
      // reposting offer residual if any - call super to let flush tokens to router
      repostStatus = super.__posthookSuccess__(order, makerData);
    }
  }
}
