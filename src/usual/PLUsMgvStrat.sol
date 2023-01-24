// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {ILiquidityProvider} from "mgv_src/strategies/interfaces/ILiquidityProvider.sol";
import {IStratEvents} from "mgv_src/strategies/interfaces/IStratEvents.sol";
import {MetaPLUsDAOToken} from "mgv_src/usual/MetaPLUsDAOToken.sol";
import {MgvLib} from "mgv_src/MgvLib.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {MangroveOffer} from "mgv_src/strategies/MangroveOffer.sol";

/// @title This contract is for Usual to create PLUsDAO / UsUSD offers through their dApp
contract PLUsMgvStrat is Direct, IStratEvents {
  /// @notice used to transfer from the maker of the offer to this contract
  IERC20 public immutable _pLUsDAOToken;

  /// @notice used for approving MetaPLUsDAOToken and creating/updating offers.
  MetaPLUsDAOToken public immutable _metaPLUsDAOToken;

  /// @notice used to paid fee and creating/updating offers.
  IERC20 public immutable _usUSD;

  /// @notice Maker address mapping
  /// @dev mapping is offerId -> Maker address
  mapping(uint => address) offerIdToMaker;

  /// @notice used to know what the address is for the dApp.
  address public _usualDapp;

  /// @notice used to keep track of the fee %.
  /// @notice Fee is in 10_000 = 100%
  uint16 public _fee = 30;

  /// @notice used to restricting the fee to be set to high.
  uint16 maxFee = 100;

  /// @notice PLUsMgvStrat constructor.
  /// @param admin the admin address for the contract.
  /// @param mgv the deployed Mangrove contract on which this contract will post offers.
  /// @param pLUsDAOToken the PLUsDAO Token needed for approval.
  /// @param metaPLUsDAOToken the MetaPLUsDAO Token used for making the offers.
  /// @param usUSD the UsUSD Token used for making the offers and paying the fee.
  constructor(address admin, IMangrove mgv, IERC20 pLUsDAOToken, MetaPLUsDAOToken metaPLUsDAOToken, IERC20 usUSD)
    Direct(mgv, NO_ROUTER, 100_000)
  {
    _pLUsDAOToken = pLUsDAOToken;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _pLUsDAOToken.approve(address(_metaPLUsDAOToken), type(uint).max);
    _usUSD = usUSD;
    if (admin != address(this)) {
      setAdmin(admin);
    }
  }

  /// @notice This modifier verifies that `msg.sender` is either the UsualDapp or the admin.
  modifier onlyDappOrAdmin() {
    require(msg.sender == _usualDapp || msg.sender == admin(), "PLUsMgvStrat/onlyDappOrAdmin");
    _;
  }

  /// @notice This sets the fee for the contract.
  /// @notice This can only be done by the admin of the contract.
  /// @dev Fee is given in 10_000 = 100%.
  /// @param fee The fee to be set.
  function setFee(uint16 fee) public onlyAdmin {
    require(fee <= maxFee, "PLUsMgvStrat/maxFee");
    _fee = fee;
    emit SetFee(fee);
  }

  /// @notice This sets the UsualDapp address.
  /// @notice This can only be done by the admin of the contract.
  /// @param usualDapp The address the new dApp contract.
  function setUsualDapp(address usualDapp) public onlyAdmin {
    _usualDapp = usualDapp;
  }

  /// @notice This withdraws all colleted fees to the `to` address.
  /// @notice This can only be done by the admin of the contract
  /// @param to The address the fees will be transfered to.
  function withdrawFees(address to) public onlyAdmin {
    debitFee(to);
  }

  /// @notice This debits the collected fees to the `to` address.
  /// @notice The function is an internal call and cannot be called by an external address.
  /// @param to The address the fees will be transfered to.
  function debitFee(address to) internal {
    uint fee = _usUSD.balanceOf(address(this));
    _usUSD.transfer(to, fee);
    emit DebitFee(fee);
  }

  /// @notice This transfers the `amount` minus the fee to the `to` address.
  /// @param amount The amount to transfer to the `to` address.
  /// @param to The address the `amount` minus the fee will be transfered to.
  function creditFee(uint amount, address to) internal {
    uint fee = (amount * _fee) / 10_000;
    _usUSD.transfer(to, amount - fee);
    emit CreditFee(fee);
  }

  /// @notice This makes the transfer of UsUSD to the maker and the transfer of PLUsDAO from the maker to this contract.
  /// @param order is a recall of the taker order that is at the origin of the current trade.
  /// @return data is a message that will be passed to posthook provided `makerExecute` does not revert.
  function __lastLook__(MgvLib.SingleOrder calldata order) internal override returns (bytes32 data) {
    address maker = offerIdToMaker[order.offerId];
    creditFee(order.gives, maker);
    _pLUsDAOToken.transferFrom(maker, address(this), order.wants);
    return "mgvOffer/proceed";
  }

  /// @notice Empty implementation of get. The transfer is handled in `__lastlook__`.
  /// @notice The standard implementation is not usable here and is therefore overridden.
  function __get__(uint, MgvLib.SingleOrder calldata) internal virtual override returns (uint missing) {
    return 0;
  }

  /// @notice This creates a new offer and saves the the connection between `offerId` and `maker`.
  /// @notice This can only be called by either the dApp or the Admin.
  /// @param wants The amount of UsUSD that the `maker` wants.
  /// @param gives The amount of (Meta)PLUsDAO that the `maker` will give.
  /// @param pivotId The id used as pivot
  /// @param maker The address saved as the maker of the offer.
  function newOffer(uint wants, uint gives, uint pivotId, address maker)
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
    offerIdToMaker[offerId] = maker;
  }

  /// @notice This skipes the Direct implementation of posthookSuccess and calls MangroveOffers implementation directly.
  /// @notice This is because the Direct implementation is not neded here and is therefore overriden.
  function __posthookSuccess__(MgvLib.SingleOrder calldata order, bytes32 makerData)
    internal
    override
    returns (bytes32)
  {
    return MangroveOffer.__posthookSuccess__(order, makerData);
  }

  /// @notice This updates the offer.
  /// @notice This can only be called by either the dApp or the Admin.
  /// @notice The `maker` has to be the owner of the offer.
  /// @param wants The amount of UsUSD that the `maker` wants.
  /// @param gives The amount of (Meta)PLUsDAO that the `maker` will give.
  /// @param pivotId The id used as pivot.
  /// @param offerId The offerId to be updated.
  /// @param maker The address saved as the maker of the offer.
  function updateOffer(uint wants, uint gives, uint pivotId, uint offerId, address maker)
    public
    payable
    onlyDappOrAdmin
    returns (bytes32)
  {
    require(offerIdToMaker[offerId] == maker, "PLUsMgvStrat/wrongOwner");
    return _updateOffer(
      OfferArgs({
        outbound_tkn: _metaPLUsDAOToken,
        inbound_tkn: _usUSD,
        wants: wants,
        gives: gives,
        gasreq: type(uint).max, // uses the old gasreg
        gasprice: 0, // ignored
        pivotId: pivotId,
        noRevert: true,
        fund: msg.value
      }),
      offerId
    );
  }
}
