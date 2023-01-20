// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {UsualTokenInterface} from "mgv_src/usual/UsualTokenInterface.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Forwarder} from "mgv_src/strategies/offer_forwarder/abstract/Forwarder.sol";
import {SimpleRouter} from "mgv_src/strategies/routers/SimpleRouter.sol";

contract PLUsMgvStrat is Forwarder {
  UsualTokenInterface public immutable _pLUsDAOToken;
  MetaPLUsDAOToken public immutable _metaPLUsDAOToken; //FIXME: could this just be an address? would it cost less gas?
  IERC20 public immutable _usUSD;
  mapping(uint => address) offerIdToOwner; // keep track of who owns the offer
  address public _usualDapp;

  constructor(
    address admin,
    IMangrove mgv,
    UsualTokenInterface pLUsDAOToken,
    MetaPLUsDAOToken metaPLUsDAOToken,
    IERC20 usUSD
  ) Forwarder(mgv, new SimpleRouter(), 1_000_000) {
    _pLUsDAOToken = pLUsDAOToken;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _pLUsDAOToken.approve(address(_metaPLUsDAOToken), type(uint).max);
    _usUSD = usUSD;
    router().bind(address(this));
    if (admin != address(this)) {
      setAdmin(admin);
      router().setAdmin(admin);
    }
  }

  modifier onlyUsualDappOrMgvOrAdmin() {
    require(
      msg.sender == _usualDapp || msg.sender == admin() || msg.sender == address(MGV),
      "PLUsMgvStrat/onlyAdminOrMgvOrDapp"
    );
    _;
  }

  function setUsualDapp(address usualDapp) public onlyAdmin {
    _usualDapp = usualDapp;
  }

  function newOffer(uint wants, uint gives, uint pivotId, address owner)
    public
    payable
    onlyUsualDappOrMgvOrAdmin
    returns (uint offerId)
  {
    offerId = _newOffer(
      OfferArgs({
        outbound_tkn: _metaPLUsDAOToken,
        inbound_tkn: _usUSD,
        wants: wants,
        gives: gives,
        gasreq: offerGasreq(),
        gasprice: 0,
        pivotId: pivotId,
        fund: msg.value,
        noRevert: false
      }),
      msg.sender
    );
    offerIdToOwner[offerId] = owner;
  }

  function __put__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint) {
    uint pushed = router().push(_usUSD, reserve(offerIdToOwner[order.offerId]), amount);
    return amount - pushed;
  }

  function __get__(uint amount, MgvLib.SingleOrder calldata order) internal virtual override returns (uint missing) {
    _pLUsDAOToken.transferFrom(offerIdToOwner[order.offerId], address(this), amount);
    return 0; // super.__get__(amount, order); //FIXME: This is not need, since we are transfering the token from the seller to this contract, in the lone before this one
  }

  function updateOffer(uint wants, uint gives, uint pivotId, uint offerId, address owner)
    public
    payable
    onlyUsualDappOrMgvOrAdmin
    returns (bytes32)
  {
    require(offerIdToOwner[offerId] == owner, "PLUsMgvStrat/wrongOwner");
    return _updateOffer(
      OfferArgs({
        outbound_tkn: _metaPLUsDAOToken,
        inbound_tkn: _usUSD,
        wants: wants,
        gives: gives,
        gasreq: type(uint).max, // uses the old gasreg
        gasprice: 0, // igonred
        pivotId: pivotId,
        noRevert: true,
        fund: msg.value
      }),
      offerId
    );
  }
}
