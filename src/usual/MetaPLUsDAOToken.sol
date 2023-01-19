// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.9;

import {IERC20} from "mgv_src/MgvLib.sol";
import {LockedWrapperToken} from "./LockedWrapperToken.sol";

// Meta-PLUsDAO token for use in demo
contract MetaPLUsDAOToken is LockedWrapperToken {
  LockedWrapperToken public immutable _lUsDAOToken;
  LockedWrapperToken public immutable _pLUsDAOToken;
  address public immutable _mangrove;
  address public _pLUsMgvStrat;

  constructor(
    address admin,
    string memory _name,
    string memory _symbol,
    LockedWrapperToken lUsDAOToken,
    LockedWrapperToken pLUsDAOToken,
    address mangrove
  ) LockedWrapperToken(admin, _name, _symbol, pLUsDAOToken) {
    _lUsDAOToken = lUsDAOToken;
    _pLUsDAOToken = pLUsDAOToken;
    _mangrove = mangrove;
  }

  function setPLUsMgvStrat(address pLUsMgvStrat) external onlyAdmin {
    _pLUsMgvStrat = pLUsMgvStrat;
  }

  function totalSupply() public view virtual override returns (uint) {
    return _pLUsDAOToken.totalSupply();
  }

  function balanceOf(address account) public view virtual override returns (uint) {
    return _pLUsDAOToken.balanceOf(account);
  }

  function approve(address spender, uint amount) public override returns (bool) {
    return _pLUsDAOToken.approve(spender, amount) && super.approve(spender, amount);
  }

  // Only allow the following transfers:
  //   any address  -> PLUsMgvStrat
  //   PLUsMgvStrat -> Mangrove
  //   Mangrove     -> any address
  // When owner = Mangrove  =>  transfer & unlock
  function _transfer(address owner, address recipient, uint amount) internal override returns (bool) {
    require(
      (
        recipient == _pLUsMgvStrat // FIXME: When will the strat be the recipient?
          || owner == _pLUsMgvStrat && recipient == _mangrove
      ) || owner == _mangrove,
      "MetaPLUsDAOToken/nonMangroveTransfer"
    );

    // if(owner == _pLUsMgvStrat && recipient == _mangrove ){
    //   return true;
    // }

    // bool result = super._transfer(owner, recipient, amount);
    // require(result, "MetaPLUsDAOToken/transferFailed");

    if (owner == _mangrove) {
      bool result = _pLUsDAOToken.transferFrom(_pLUsMgvStrat, recipient, amount);
      require(result, "MetaPLUsDAOToken/transferFailed");
      // _pLUsDAOToken.transferFrom(owner, recipient, amount);
      // _unlockFor(recipient, amount);
      result = _pLUsDAOToken.unlockFor(recipient, amount);
      require(result, "MetaPLUsDAOToken/PLUsDAOUnlockFailed");
    }

    return true;
  }
}
