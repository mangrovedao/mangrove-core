pragma solidity ^0.8.14;

import {Direct, IMangrove, IERC20} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {LockedWrapperToken} from "mgv_src/usual/LockedWrapperToken.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";

// This is a simple strat for demo purposes.
// FIXME: This strat should handle the MetaPLUsDAO -> PLUsDAO token mapping, but for now it just relies on a workaround in MetaPLUsDAO token that allows it to be used directly.
//        Also, the posting of offers should be simpler (no specification of tokens needed for one market) but mangrove.js doesn't support that out-of-the-box
contract PLUsMgvStrat is ILiquidityProvider, Direct {
  LockedWrapperToken public immutable _pLUsDAOToken;
  MetaPLUsDAOToken public immutable _metaPLUsDAOToken;
  // IERC20 public immutable _usUSD;

  // FIXME: Use a simple constructor for now
  // constructor(address admin, IMangrove mgv, LockedWrapperToken pLUsDAOToken, MetaPLUsDAOToken metaPLUsDAOToken, IERC20 usUSD)
  //   Direct(mgv, NO_ROUTER, 40_000)
  // {
  //   _pLUsDAOToken = pLUsDAOToken;
  //   _metaPLUsDAOToken = metaPLUsDAOToken;
  //   _usUSD = usUSD;
  // }

  constructor(IMangrove mgv, LockedWrapperToken pLUsDAOToken, MetaPLUsDAOToken metaPLUsDAOToken)
    Direct(mgv, NO_ROUTER, 1_000_000)
  {
    _pLUsDAOToken = pLUsDAOToken;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _pLUsDAOToken.approve(address(_metaPLUsDAOToken), type(uint).max);
  }

  // FIXME: For now, we use the IMakerLogic signature of newOffer which mangrove.js supports directly
  function newOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId
  ) public payable override mgvOrAdmin returns (uint offerId) {
    _pLUsDAOToken.depositFrom(msg.sender, msg.sender, gives);
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: outbound_tkn,
        inbound_tkn: inbound_tkn,
        wants: wants,
        gives: gives,
        gasreq: gasreq,
        gasprice: gasprice,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false,
        owner: msg.sender
      })
    );
  }

  // deposit from PLUsDAO to Meta-PLUsDAO
  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint missing) {
    _metaPLUsDAOToken.depositFrom(admin(), address(this), amount);
    return super.__get__(amount, order);
  }

  function updateOffer(
    IERC20 outbound_tkn,
    IERC20 inbound_tkn,
    uint wants,
    uint gives,
    uint gasreq,
    uint gasprice,
    uint pivotId,
    uint offerId
  ) public payable {}
}
