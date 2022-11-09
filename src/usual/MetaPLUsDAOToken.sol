pragma solidity ^0.8.14;

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
  )
    LockedWrapperToken(admin, _name, _symbol, pLUsDAOToken)
  {
    _lUsDAOToken = lUsDAOToken;
    _pLUsDAOToken = pLUsDAOToken;
    _mangrove = mangrove;
  }

  function setPLUsMgvStrat(address pLUsMgvStrat) external onlyAdmin {
    _pLUsMgvStrat = pLUsMgvStrat;
  }

  function totalSupply() public view virtual override returns (uint) {
    return _lUsDAOToken.totalSupply() + _pLUsDAOToken.totalSupply() + super.totalSupply();
  }

  function balanceOf(address account) public view virtual override returns (uint) {
    return _lUsDAOToken.balanceOf(account) + _pLUsDAOToken.balanceOf(account) + super.balanceOf(account);
  }

  // Only allow the following transfers:
  //   any address  -> PLUsMgvStrat
  //   PLUsMgvStrat -> Mangrove
  //   Mangrove     -> any address
  // When owner = Mangrove  =>  transfer & unlock
  function _transfer(address owner, address recipient, uint amount)
    internal override returns (bool)
  {
    require(
      (  recipient == _pLUsMgvStrat
      || owner == _pLUsMgvStrat && recipient == _mangrove)
      || owner == _mangrove, "MetaPLUsDAOToken/nonMangroveTransfer"
    );
    bool result = super._transfer(owner, recipient, amount);
    require(result, "MetaPLUsDAOToken/transferFailed");

    if (owner == _mangrove) {
      _unlockFor(recipient, amount);
      result = _pLUsDAOToken.unlockFor(recipient, amount);
      require(result, "MetaPLUsDAOToken/PLUsDAOUnlockFailed");
    }

    return true;
  }
}
