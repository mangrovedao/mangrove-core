pragma solidity ^0.8.14;

import {Direct} from "mgv_src/strategies/offer_maker/abstract/Direct.sol";
import {IERC20} from "mgv_src/MgvLib.sol";
import {IMangrove} from "mgv_src/IMangrove.sol";
import {LockedWrapperToken} from "mgv_src/usual/LockedWrapperToken.sol";

contract PLUsMgvStrat is Direct {
  LockedWrapperToken public immutable _pLUsDAOToken;
  IERC20 public immutable _usUSD;

  constructor(address admin, IMangrove mgv, LockedWrapperToken pLUsDAOToken, IERC20 usUSD)
    Direct(mgv, NO_ROUTER, 100_000)
  {
    setAdmin(admin);
    _pLUsDAOToken = pLUsDAOToken;
    _usUSD = usUSD;
  }
}
