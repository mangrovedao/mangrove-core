// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {PLUsMgvStrat} from "mgv_src/usual/PLUsMgvStrat.sol";

contract UsualDapp {
  PLUsMgvStrat _pLUsMgvStrat;
  address public immutable _admin;

  constructor(address admin) {
    _admin = admin;
  }

  modifier onlyAdmin() {
    require(msg.sender == _admin, "MetaPLUsDAOToken/adminOnly");
    _;
  }

  function setPLUsMgvStrat(PLUsMgvStrat pLUsMgvStrat) external onlyAdmin {
    _pLUsMgvStrat = pLUsMgvStrat;
  }

  function newOffer(uint wants, uint gives, uint pivotId) public payable returns (uint offerId) {
    return _pLUsMgvStrat.newOffer{value: msg.value}(wants, gives, pivotId, msg.sender);
  }
}
