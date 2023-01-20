// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.14;

import {IMangrove} from "mgv_src/IMangrove.sol";
import {IERC20} from "mgv_src/IERC20.sol";

contract PLUsTakerProxy {
  IMangrove public immutable _mgv;
  IERC20 public immutable _metaPLUsDAOToken;
  IERC20 public immutable _usUSD;
  address public currentTaker;

  receive() external payable virtual {}

  constructor(IMangrove mgv, IERC20 metaPLUsDAOToken, IERC20 usUSD) {
    _mgv = mgv;
    _metaPLUsDAOToken = metaPLUsDAOToken;
    _usUSD = usUSD;
    _usUSD.approve(address(_mgv), type(uint).max);
  }

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
