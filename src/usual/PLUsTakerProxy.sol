// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

/// @title The contract is the Proxy taker for UsualDAO.
/// @notice This contract is only for making market orders and preveting sniping of offers.
contract PLUsTakerProxy {
  /// @notice This is the Mangrove instance used.
  IMangrove public immutable _mgv;

  /// @notice This is the MetaPLUsDAO Token used as outbound token to the send the market order.
  IERC20 public immutable _metaPLUsDAOToken;

  /// @notice This is the UsUSD Token used as inbound token to the send the market order.
  IERC20 public immutable _usUSD;

  /// @notice This is used to keep track of the current taker.
  address public currentTaker;

  /// @notice This is used in order for the contract to be able to recieve any bounties.
  receive() external payable virtual {}

  /// @notice PLUsTakerProxy contructor.
  /// @param mgv The Mangrove instance used.
  /// @param metaPLUsDAOToken The MetaPLUsDAO Token used as outbound token.
  /// @param usUSD The UsUSD Token used as inbound token.
  constructor(IMangrove mgv, IERC20 metaPLUsDAOToken, IERC20 usUSD) {
    _mgv = mgv;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _usUSD = usUSD;
    _usUSD.approve(address(_mgv), type(uint).max);
  }

  /// @notice This keeps track of the current taker, sends a marketOrder and sends any bounty back to the taker.
  /// @notice The taker could be a contract that would call this method again when receiving the bounty. This is not an issue.
  /// @param takerWants The amount the taker wants in (Meta)PLUsDAO
  /// @param takerGives The amount the taker gives in UsUSD
  function marketOrder(uint takerWants, uint takerGives)
    public
    returns (uint takerGot, uint takerGave, uint bounty, uint feePaid)
  {
    currentTaker = msg.sender;
    _usUSD.transferFrom(msg.sender, address(this), takerGives);
    (takerGot, takerGave, bounty, feePaid) = _mgv.marketOrder({
      outbound_tkn: address(_metaPLUsDAOToken),
      inbound_tkn: address(_usUSD),
      takerWants: takerWants,
      takerGives: takerGives,
      fillWants: true
    });
    if (bounty > 0) {
      (bool noRevert,) = msg.sender.call{value: bounty}("");
      require(noRevert, "mgv/sendPenaltyReverted");
    }
    currentTaker = address(0);
  }
}
