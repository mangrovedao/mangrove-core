// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.9;

import {ERC20Base, ERC20} from "mgv_src/toy/ERC20.sol";
import {UsualTokenInterface} from "mgv_src/usual/UsualTokenInterface.sol";
import {PLUsTakerProxy} from "mgv_src/usual/PLUsTakerProxy.sol";

// Meta-PLUsDAO token for use in demo
contract MetaPLUsDAOToken is ERC20 {
  UsualTokenInterface public immutable _pLUsDAOToken;
  PLUsTakerProxy public _pLUsTakerProxy;
  address public immutable _mangrove;
  address public _pLUsMgvStrat;
  address public _admin;

  constructor(
    address admin,
    string memory _name,
    string memory _symbol,
    UsualTokenInterface pLUsDAOToken,
    address mangrove
  ) ERC20Base(_name, _symbol) ERC20(_name) {
    _pLUsDAOToken = pLUsDAOToken;
    _mangrove = mangrove;
    _admin = admin;
  }

  modifier onlyAdmin() {
    require(msg.sender == _admin, "MetaPLUsDAOToken/adminOnly");
    _;
  }

  function setPLUsTakerProxy(PLUsTakerProxy pLUsTakerProxy) external onlyAdmin {
    _pLUsTakerProxy = pLUsTakerProxy;
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
  //   PLUsMgvStrat -> Mangrove
  //   Mangrove     -> any address
  // When owner = Mangrove  =>  transfer & unlock
  function _transfer(address owner, address recipient, uint amount) internal override returns (bool) {
    require(
      (recipient == _pLUsMgvStrat || owner == _pLUsMgvStrat && recipient == _mangrove)
        || owner == _mangrove && recipient == address(_pLUsTakerProxy),
      "MetaPLUsDAOToken/nonMangroveTransfer"
    );
    // emit the empty transfer?

    if (owner == _mangrove) {
      address currentTaker = _pLUsTakerProxy.currentTaker();
      bool result = _pLUsDAOToken.transferFrom(_pLUsMgvStrat, currentTaker, amount);
      require(result, "MetaPLUsDAOToken/transferFailed");
      result = _pLUsDAOToken.unlockFor(currentTaker, amount);
      require(result, "MetaPLUsDAOToken/PLUsDAOUnlockFailed");
    }

    return true;
  }
}
