// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "mgv_src/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract MgvGlobalTest is Test {

  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function test_pack(address monitor, bool useOracle, bool notify, uint gasprice, uint gasmax, bool dead) public {
    MgvStructs.GlobalPacked packed = MgvStructs.Global.pack(monitor, useOracle, notify, gasprice, gasmax, dead);
    assertEq(packed.monitor(),monitor,"bad monitor");
    assertEq(packed.useOracle(),useOracle,"bad useOracle");
    assertEq(packed.notify(),notify,"bad notify");
    assertEq(packed.gasprice(),cast(gasprice,16),"bad gasprice");
    assertEq(packed.gasmax(),cast(gasmax,24),"bad gasmax");
    assertEq(packed.dead(),dead,"bad dead");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_monitor(MgvStructs.GlobalPacked packed,address monitor) public {
      MgvStructs.GlobalPacked original = packed.monitor(packed.monitor());
      assertEq(original.monitor(),packed.monitor(), "original: bad monitor");

      MgvStructs.GlobalPacked modified = packed.monitor(monitor);

      assertEq(modified.monitor(),monitor,"modified: bad monitor");

      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
    }
  function test_set_useOracle(MgvStructs.GlobalPacked packed,bool useOracle) public {
      MgvStructs.GlobalPacked original = packed.useOracle(packed.useOracle());
      assertEq(original.useOracle(),packed.useOracle(), "original: bad useOracle");

      MgvStructs.GlobalPacked modified = packed.useOracle(useOracle);

      assertEq(modified.useOracle(),useOracle,"modified: bad useOracle");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
    }
  function test_set_notify(MgvStructs.GlobalPacked packed,bool notify) public {
      MgvStructs.GlobalPacked original = packed.notify(packed.notify());
      assertEq(original.notify(),packed.notify(), "original: bad notify");

      MgvStructs.GlobalPacked modified = packed.notify(notify);

      assertEq(modified.notify(),notify,"modified: bad notify");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
    }
  function test_set_gasprice(MgvStructs.GlobalPacked packed,uint gasprice) public {
      MgvStructs.GlobalPacked original = packed.gasprice(packed.gasprice());
      assertEq(original.gasprice(),packed.gasprice(), "original: bad gasprice");

      MgvStructs.GlobalPacked modified = packed.gasprice(gasprice);

      assertEq(modified.gasprice(),cast(gasprice,16),"modified: bad gasprice");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
    }
  function test_set_gasmax(MgvStructs.GlobalPacked packed,uint gasmax) public {
      MgvStructs.GlobalPacked original = packed.gasmax(packed.gasmax());
      assertEq(original.gasmax(),packed.gasmax(), "original: bad gasmax");

      MgvStructs.GlobalPacked modified = packed.gasmax(gasmax);

      assertEq(modified.gasmax(),cast(gasmax,24),"modified: bad gasmax");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
    }
  function test_set_dead(MgvStructs.GlobalPacked packed,bool dead) public {
      MgvStructs.GlobalPacked original = packed.dead(packed.dead());
      assertEq(original.dead(),packed.dead(), "original: bad dead");

      MgvStructs.GlobalPacked modified = packed.dead(dead);

      assertEq(modified.dead(),dead,"modified: bad dead");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
    }

  function test_unpack(MgvStructs.GlobalPacked packed) public {
    (address monitor, bool useOracle, bool notify, uint gasprice, uint gasmax, bool dead) = packed.unpack();

    assertEq(packed.monitor(),monitor,"bad monitor");
    assertEq(packed.useOracle(),useOracle,"bad useOracle");
    assertEq(packed.notify(),notify,"bad notify");
    assertEq(packed.gasprice(),gasprice,"bad gasprice");
    assertEq(packed.gasmax(),gasmax,"bad gasmax");
    assertEq(packed.dead(),dead,"bad dead");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(MgvStructs.GlobalPacked packed) public {
    MgvStructs.GlobalUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.monitor,packed.monitor(),"bad monitor");
    assertEq(unpacked.useOracle,packed.useOracle(),"bad useOracle");
    assertEq(unpacked.notify,packed.notify(),"bad notify");
    assertEq(unpacked.gasprice,packed.gasprice(),"bad gasprice");
    assertEq(unpacked.gasmax,packed.gasmax(),"bad gasmax");
    assertEq(unpacked.dead,packed.dead(),"bad dead");
  }

  function test_inverse_2(MgvStructs.GlobalUnpacked memory unpacked) public {
    MgvStructs.GlobalPacked packed = MgvStructs.Global.t_of_struct(unpacked);
    MgvStructs.GlobalPacked packed2;
    packed2 = packed2.monitor(unpacked.monitor);
    packed2 = packed2.useOracle(unpacked.useOracle);
    packed2 = packed2.notify(unpacked.notify);
    packed2 = packed2.gasprice(unpacked.gasprice);
    packed2 = packed2.gasmax(unpacked.gasmax);
    packed2 = packed2.dead(unpacked.dead);
    assertEq(packed.monitor(),packed2.monitor(),"bad monitor");
    assertEq(packed.useOracle(),packed2.useOracle(),"bad useOracle");
    assertEq(packed.notify(),packed2.notify(),"bad notify");
    assertEq(packed.gasprice(),packed2.gasprice(),"bad gasprice");
    assertEq(packed.gasmax(),packed2.gasmax(),"bad gasmax");
    assertEq(packed.dead(),packed2.dead(),"bad dead");
  }
}
