// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

/**
 * @notice This contract provides a collection of interactions capabilities with AAVE-v3 to whichever contract inherits it
 */
/**
 * `AaveV3Borrower` contracts are in particular able to perfom basic pool interactions (lending, borrowing, supplying and repaying)
 */

import {IERC20, AaveV3Lender} from "./AaveV3Lender.sol";
import {DataTypes} from "mgv_src/strategies/vendor/aave/v3/DataTypes.sol";
import {IPriceOracleGetter} from "mgv_src/strategies/vendor/aave/v3/IPriceOracleGetter.sol";
import {IPoolAddressesProvider} from "mgv_src/strategies/vendor/aave/v3/IPoolAddressesProvider.sol";

contract AaveV3Borrower is AaveV3Lender {
  /**
   * @notice address of AAVE price oracle (must be the price oracle used by the pool)
   */
  /**
   * @dev price oracle and pool address can be obtained from AAVE's address provider contract
   */
  IPriceOracleGetter public immutable ORACLE;
  uint public immutable INTEREST_RATE_MODE;
  uint16 public constant REFERRAL_CODE = uint16(0);

  /**
   * @notice contract's constructor
   * @param _addressesProvider address of AAVE's address provider
   * @param _interestRateMode interest rate mode for borrowing assets. 0 for none, 1 for stable, 2 for variable
   */
  constructor(address _addressesProvider, uint _interestRateMode) AaveV3Lender(_addressesProvider) {
    INTEREST_RATE_MODE = _interestRateMode;

    address _priceOracle = IPoolAddressesProvider(_addressesProvider).getAddress("PRICE_ORACLE");
    require(_priceOracle != address(0), "AaveModule/0xPriceOracle");
    ORACLE = IPriceOracleGetter(_priceOracle);
  }

  ///@notice tries to borrow some assets from the pool
  ///@param token the asset one is borrowing
  ///@param onBehalf the account whose collateral is being used to borrow (caller must be approved by `onBehalf` -if different- using `approveDelegation` from the corresponding debt token (variable or stable))
  function _borrow(IERC20 token, uint amount, address onBehalf, bool noRevert) internal returns (bytes32) {
    try POOL.borrow(address(token), amount, INTEREST_RATE_MODE, REFERRAL_CODE, onBehalf) {
      return bytes32(0);
    } catch Error(string memory reason) {
      require(noRevert, reason);
      return bytes32(bytes(reason));
    }
  }

  ///@notice repays debt to the pool
  ///@param token the asset one is repaying
  ///@param amount of assets one is repaying
  ///@param onBehalf account whose debt is being repaid
  function _repay(IERC20 token, uint amount, address onBehalf, bool noRevert) internal returns (uint, bytes32) {
    try POOL.repay(address(token), amount, INTEREST_RATE_MODE, onBehalf) returns (uint repaid) {
      return (repaid, bytes32(0));
    } catch Error(string memory reason) {
      require(noRevert, reason);
      return (0, bytes32(bytes(reason)));
    }
  }
}
