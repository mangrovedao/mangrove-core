// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {IStratEvents} from "mgv_src/strategies/interfaces/IStratEvents.sol";
import {UsualTokenInterface} from "mgv_src/usual/UsualTokenInterface.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";

contract PLUsMgvStrat is Direct, IStratEvents {
  UsualTokenInterface public immutable _pLUsDAOToken;
  MetaPLUsDAOToken public immutable _metaPLUsDAOToken;
  IERC20 public immutable _usUSD;
  mapping(uint => address) offerIdToOwner; // keep track of who owns the offer
  address public _usualDapp;
  uint16 public _fee = 30; // Fee is in 10_000 = 100%
  uint16 maxFee = 100;

  constructor(
    address admin,
    IMangrove mgv,
    UsualTokenInterface pLUsDAOToken,
    MetaPLUsDAOToken metaPLUsDAOToken,
    IERC20 usUSD
  ) Direct(mgv, NO_ROUTER, 100_000) {
    _pLUsDAOToken = pLUsDAOToken;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _pLUsDAOToken.approve(address(_metaPLUsDAOToken), type(uint).max);
    _usUSD = usUSD;
    if (admin != address(this)) {
      setAdmin(admin);
    }
  }

  modifier onlyDappOrAdmin() {
    require(msg.sender == _usualDapp || msg.sender == admin(), "PLUsMgvStrat/onlyDappOrAdmin");
    _;
  }

  function setFee(uint16 fee) public onlyAdmin {
    require(fee <= maxFee, "PLUsMgvStrat/maxFee");
    _fee = fee;
    emit SetFee(fee);
  }

  function setUsualDapp(address usualDapp) public onlyAdmin {
    _usualDapp = usualDapp;
  }

  function withdrawFees(address to) public onlyAdmin {
    debitFee(to);
  }

  function debitFee(address to) internal {
    uint fee = _usUSD.balanceOf(address(this));
    _usUSD.transfer(to, fee);
    emit DebitFee(fee);
  }

  function creditFee(uint amount, address owner) internal {
    uint fee = (amount * _fee) / 10_000;
    _usUSD.transfer(owner, amount - fee);
    emit CreditFee(fee);
  }

  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32 data) {
    address owner = offerIdToOwner[order.offerId];
    creditFee(order.gives, owner);
    _pLUsDAOToken.transferFrom(owner, address(this), order.wants);
    return "mgvOffer/proceed";
  }

  function __put__(uint, MgvLib.SingleOrder calldata) internal virtual override returns (uint) {
    return 0;
  }

  function __get__(uint, MgvLib.SingleOrder calldata) internal virtual override returns (uint missing) {
    return 0;
  }

  function newOffer(uint wants, uint gives, uint pivotId, address owner)
    public
    payable
    onlyDappOrAdmin
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
      })
    );
    offerIdToOwner[offerId] = owner;
  }

  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    return MangroveOffer.__posthookSuccess__(order, makerData);
  }

  function updateOffer(uint wants, uint gives, uint pivotId, uint offerId, address owner)
    public
    payable
    onlyDappOrAdmin
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
