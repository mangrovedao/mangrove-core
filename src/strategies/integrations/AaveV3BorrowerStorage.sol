// SPDX-License-Identifier:	BSD-2-Clause
pragma solidity ^0.8.10;

import "../vendor/aave/v3/IPool.sol";
import {IPoolAddressesProvider} from "../vendor/aave/v3/IPoolAddressesProvider.sol";
import {IRewardsControllerIsh} from "../vendor/aave/v3/IRewardsControllerIsh.sol";
import {ICreditDelegationToken} from "../vendor/aave/v3/ICreditDelegationToken.sol";

import "../vendor/aave/v3/IPriceOracleGetter.sol";
import {ReserveConfiguration as RC} from "../vendor/aave/v3/ReserveConfiguration.sol";

import "mgv_src/IMangrove.sol";

library AaveV3BorrowerStorage {
  // address of the lendingPool
  // struct Layout {
  // }

  // function getStorage() internal pure returns (Layout storage st) {
  //   bytes32 storagePosition = keccak256(
  //     "Mangrove.AaveV3BorrowerStorageLib.Layout"
  //   );
  //   assembly {
  //     st.slot := storagePosition
  //   }
  // }

  function revertWithData(bytes memory retdata) internal pure {
    if (retdata.length == 0) {
      revert("AaveModuleStorage/revertNoReason");
    }
    assembly {
      revert(add(retdata, 32), mload(retdata))
    }
  }
}
