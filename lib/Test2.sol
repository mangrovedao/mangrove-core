// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Test, console2} from "@mgv/forge-std/Test.sol";
import "@mgv/lib/Script2.sol";

/* Some ease-of-life additions to forge-std/Test.sol */
/* You may want to inherit `MangroveTest` (which inherits `Test2`) rather than inherit `Test2` directly */
contract Test2 is Test, Script2 {
  /* *** Pranking save/restore ***

    Does not support nesting.

    Returns msg.sender, used to capture the current prank value.
    The recipe is: save prank address, do a call, reprank.
    except if prank address is current address. Then just don't reprank and the result will be the same
  */
  struct SavedPrank {
    uint mode; // 0 is do nothing, 1 is do prank, 2 is do startPrank
    address addr;
  }

  SavedPrank savedPrank;

  function echoSender() external view returns (address) {
    return msg.sender;
  }

  /* save current prank address if any
     inside a `startPrank`, can `suspend` pranking */
  function savePrank(bool suspend) internal {
    savedPrank.mode = 0;
    savedPrank.addr = this.echoSender();
    if (savedPrank.addr != address(this)) {
      // pranking a different address
      if (savedPrank.addr != this.echoSender()) {
        // in a onetime vm.prank
        savedPrank.mode = 1;
      } else if (suspend) {
        // in vm.startPrank, will suspend
        savedPrank.mode = 2;
        vm.stopPrank();
      }
    }
  }

  // sugar for simple save
  function savePrank() internal {
    savePrank(false);
  }

  /* restore prank */
  function restorePrank() internal {
    if (savedPrank.mode == 1) {
      vm.prank(savedPrank.addr);
    } else if (savedPrank.mode == 2) {
      vm.startPrank(savedPrank.addr);
    }
  }

  /* *** Test & cheatcode helpers **** */

  modifier prank(address a) {
    vm.startPrank(a);
    _;
    vm.stopPrank();
  }

  /* sugar for successful test */
  function succeed() internal {
    assertTrue(true);
  }

  // both mock a call and expect the call to happen
  function expectToMockCall(address addr, bytes memory req, bytes memory res) internal {
    vm.mockCall(addr, req, res);
    vm.expectCall(addr, req);
  }

  uint keyIterator = 1;

  /* Create addr/key pairs, with/without label.

     Used in favor of std-forge's makeAddrAndKey/makeAddr,
     because it ensures freshness, the label is optional, and
     does not have to be unique.

     Variants:
     freshAccount(label)       labeled key,address
     freshAccount()            key,address
     freshKey()                key
     freshAddress(label)       labeled address
     freshAddress()            address
  */
  function freshAccount(string memory label) internal returns (uint key, address payable addr) {
    unchecked {
      key = (keyIterator++) + uint(keccak256(bytes(label)));
    }
    addr = payable(vm.addr(key));

    // set code to nonzero so solidity-inserted extcodesize checks don't fail
    vm.etch(addr, bytes("not zero"));
    vm.label(addr, string.concat("fresh-address:",label));
    return (key, addr);
  }

  function freshAccount() internal returns (uint, address payable) {
    return freshAccount(vm.toString(keyIterator));
  }

  function freshKey() internal returns (uint key) {
    (key,) = freshAccount();
  }

  function freshAddress(string memory label) internal returns (address payable addr) {
    (, addr) = freshAccount(label);
  }

  function freshAddress() internal returns (address payable addr) {
    (, addr) = freshAccount();
  }

  /* expect exact log from address */
  function expectFrom(address addr) internal {
    vm.expectEmit(true, true, true, true, addr);
  }

  /* assert address is not 0 */
  function assertNot0x(address a) internal returns (bool) {
    if (a == address(0)) {
      emit log("Error: address should not be 0");
      emit log_named_address("Address", a);
      fail();
    }
    return (a != address(0));
  }

  /* *** Gas Metering *** */

  uint private checkpointGasLeft;
  /* start measuring gas */

  function _gas() internal virtual {
    vm.pauseGasMetering();
    checkpointGasLeft = gasleft();
    vm.resumeGasMetering();
  }

  /* stop measuring gas and report */
  function gas_() internal virtual returns (uint) {
    vm.pauseGasMetering();
    uint checkpointGasLeft2 = gasleft();

    uint gasDelta = checkpointGasLeft - checkpointGasLeft2;
    vm.resumeGasMetering();

    // emit log_named_uint("Gas used", gasDelta);
    console2.log("Gas used: %s", gasDelta);
    return gasDelta;
  }

  function gas_(string memory gasLabel) internal virtual returns (uint) {
    vm.pauseGasMetering();
    uint checkpointGasLeft2 = gasleft();

    uint gasDelta = checkpointGasLeft - checkpointGasLeft2;
    vm.resumeGasMetering();

    console2.log("Gas used in: %s: %s", gasLabel, gasDelta);
    // emit log_named_uint(string.concat("Gas used in: ",msg), gasDelta);
    return gasDelta;
  }

  function gas_(bool silent) internal virtual returns (uint) {
    vm.pauseGasMetering();
    uint checkpointGasLeft2 = gasleft();

    uint gasDelta = checkpointGasLeft - checkpointGasLeft2;
    vm.resumeGasMetering();

    // emit log_named_uint("Gas used", gasDelta);
    if (!silent) {
      console2.log("Gas used: %s", gasDelta);
    }
    return gasDelta;
  }

  function measureTransferGas(address tkn) public returns (uint) {
    address someone = freshAddress();
    vm.prank(someone);
    IERC20(tkn).approve(address(this), type(uint).max);
    deal(tkn, someone, 10);
    /* WARNING: gas metering is done by local execution, which means that on
     * networks that have different EIPs activated, there will be discrepancies. */
    uint post;
    uint pre = gasleft();
    IERC20(tkn).transferFrom(someone, address(this), 1);
    post = gasleft();
    return pre - post;
  }

  // Returns a relative error in basis points, to be used by assertApproxEqRel*
  function relError(uint basis_points) internal pure returns (uint) {
    return 1e18*basis_points/10_000;
  }
}
