pragma solidity ^0.8.14;

import {IERC20} from "mgv_src/MgvLib.sol";
import {LockedWrapperToken} from "./LockedWrapperToken.sol";

// Meta-PLUsDAO token for use in demo
contract MetaPLUsDAOToken is IERC20 {
  mapping(address => bool) public admins;
  mapping(address => mapping(address => uint)) private _allowances;

  string private __symbol;
  string private __name;

  LockedWrapperToken public immutable _pLUsDAOToken;
  address public immutable _mangrove;
  address public immutable _pLUsMgvStrat;

  constructor(
    address admin,
    string memory _name,
    string memory _symbol,
    LockedWrapperToken pLUsDAOToken,
    address mangrove,
    address pLUsMgvStrat
  ) {
    admins[admin] = true;
    __symbol = _symbol;
    __name = _name;
    _pLUsDAOToken = pLUsDAOToken;
    _mangrove = mangrove;
    _pLUsMgvStrat = pLUsMgvStrat;
  }

  modifier onlyAdmin() {
    require(admins[msg.sender], "MetaPLUsDAOToken/adminOnly");
    _;
  }

  function addAdmin(address admin) external onlyAdmin {
    admins[admin] = true;
  }

  function removeAdmin(address admin) external onlyAdmin {
    admins[admin] = false;
  }

  function name() public view virtual returns (string memory) {
    return __name;
  }

  function symbol() external view returns (string memory) {
    return __symbol;
  }

  function decimals() external view returns (uint8) {
    return _pLUsDAOToken.decimals();
  }

  function totalSupply() external view returns (uint) {
    return _pLUsDAOToken.totalSupply();
  }

  function balanceOf(address account) external view returns (uint) {
    return _pLUsDAOToken.balanceOf(account);
  }

  function transfer(address recipient, uint amount) external returns (bool) {
    return _transfer(msg.sender, recipient, amount);
  }

  function allowance(address owner, address spender) external view returns (uint) {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint amount) external returns (bool) {
    _allowances[msg.sender][spender] = amount;
    emit Approval(msg.sender, spender, amount);
    return true;
  }

  function transferFrom(address owner, address recipient, uint amount) external returns (bool) {
    uint currentAllowance = _allowances[owner][msg.sender];
    if (currentAllowance != type(uint).max) {
      require(currentAllowance >= amount, "insufficient allowance");
      _allowances[owner][msg.sender] = currentAllowance - amount;
    }

    return _transfer(owner, recipient, amount);
  }

  // Only allow the following transfers:
  // - PLUsMgvStrat -> Mangrove
  // - Mangrove     -> any address
  // When owner = Mangrove  =>  transfer & unlock
  function _transfer(address owner, address recipient, uint amount) internal returns (bool) {
    require(
      (owner == _pLUsMgvStrat && recipient == _mangrove) || owner == _mangrove, "MetaPLUsDAOToken/nonMangroveTransfer"
    );
    bool result = _pLUsDAOToken.transferFrom(owner, recipient, amount);
    if (!result) {
      revert("MetaPLUsDAOToken/PLUsDAOTransferFailed");
    }
    if (owner == _mangrove) {
      result = _pLUsDAOToken.withdrawTo(recipient, amount);
      if (!result) {
        revert("MetaPLUsDAOToken/PLUsDAOUnlockFailed");
      }
    }

    return true;
  }

  // FIXME: Only here for demo purposes
  function mint(address to, uint amount) external override returns (bool) {
    revert("mintNotAllowed");
  }

}
