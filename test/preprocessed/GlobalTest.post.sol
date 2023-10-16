// SPDX-License-Identifier:	AGPL-3.0

pragma solidity ^0.8.13;

import "@mgv/lib/Test2.sol";
import "@mgv/src/core/MgvLib.sol";

// Warning: fuzzer will run tests with malformed packed arguments, e.g. bool fields that are > 1.

contract GlobalTest is Test2 {

  // cleanup arguments with variable number of bits since `pack` also does a cleanup
  function cast(uint u, uint8 to) internal pure returns (uint) {
    return u & (type(uint).max >> (256-to));
  }

  function cast(int u, uint8 to) internal pure returns (int) {
    return u << (256-to) >> (256-to);
  }

  function test_pack(address monitor, bool useOracle, bool notify, uint gasprice, uint gasmax, bool dead, uint maxRecursionDepth, uint maxGasreqForFailingOffers) public {
    Global packed = GlobalLib.pack(monitor, useOracle, notify, gasprice, gasmax, dead, maxRecursionDepth, maxGasreqForFailingOffers);
    assertEq(packed.monitor(),monitor,"bad monitor");
    assertEq(packed.useOracle(),useOracle,"bad useOracle");
    assertEq(packed.notify(),notify,"bad notify");
    assertEq(packed.gasprice(),cast(gasprice,26),"bad gasprice");
    assertEq(packed.gasmax(),cast(gasmax,24),"bad gasmax");
    assertEq(packed.dead(),dead,"bad dead");
    assertEq(packed.maxRecursionDepth(),cast(maxRecursionDepth,8),"bad maxRecursionDepth");
    assertEq(packed.maxGasreqForFailingOffers(),cast(maxGasreqForFailingOffers,32),"bad maxGasreqForFailingOffers");
  }

  /* test_set_x tests:
     - setting works
     - get(set(get(x))) = get(x)
     - dirty bit cleaning 
     - no additional bits being dirtied
  */
  function test_set_monitor(Global packed,address monitor) public {
      Global original = packed.monitor(packed.monitor());
      assertEq(original.monitor(),packed.monitor(), "original: bad monitor");

      Global modified = packed.monitor(monitor);

      assertEq(modified.monitor(),monitor,"modified: bad monitor");

      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_useOracle(Global packed,bool useOracle) public {
      Global original = packed.useOracle(packed.useOracle());
      assertEq(original.useOracle(),packed.useOracle(), "original: bad useOracle");

      Global modified = packed.useOracle(useOracle);

      assertEq(modified.useOracle(),useOracle,"modified: bad useOracle");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_notify(Global packed,bool notify) public {
      Global original = packed.notify(packed.notify());
      assertEq(original.notify(),packed.notify(), "original: bad notify");

      Global modified = packed.notify(notify);

      assertEq(modified.notify(),notify,"modified: bad notify");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_gasprice(Global packed,uint gasprice) public {
      Global original = packed.gasprice(packed.gasprice());
      assertEq(original.gasprice(),packed.gasprice(), "original: bad gasprice");

      Global modified = packed.gasprice(gasprice);

      assertEq(modified.gasprice(),cast(gasprice,26),"modified: bad gasprice");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_gasmax(Global packed,uint gasmax) public {
      Global original = packed.gasmax(packed.gasmax());
      assertEq(original.gasmax(),packed.gasmax(), "original: bad gasmax");

      Global modified = packed.gasmax(gasmax);

      assertEq(modified.gasmax(),cast(gasmax,24),"modified: bad gasmax");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_dead(Global packed,bool dead) public {
      Global original = packed.dead(packed.dead());
      assertEq(original.dead(),packed.dead(), "original: bad dead");

      Global modified = packed.dead(dead);

      assertEq(modified.dead(),dead,"modified: bad dead");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_maxRecursionDepth(Global packed,uint maxRecursionDepth) public {
      Global original = packed.maxRecursionDepth(packed.maxRecursionDepth());
      assertEq(original.maxRecursionDepth(),packed.maxRecursionDepth(), "original: bad maxRecursionDepth");

      Global modified = packed.maxRecursionDepth(maxRecursionDepth);

      assertEq(modified.maxRecursionDepth(),cast(maxRecursionDepth,8),"modified: bad maxRecursionDepth");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(),"modified: bad maxGasreqForFailingOffers");
    }
  function test_set_maxGasreqForFailingOffers(Global packed,uint maxGasreqForFailingOffers) public {
      Global original = packed.maxGasreqForFailingOffers(packed.maxGasreqForFailingOffers());
      assertEq(original.maxGasreqForFailingOffers(),packed.maxGasreqForFailingOffers(), "original: bad maxGasreqForFailingOffers");

      Global modified = packed.maxGasreqForFailingOffers(maxGasreqForFailingOffers);

      assertEq(modified.maxGasreqForFailingOffers(),cast(maxGasreqForFailingOffers,32),"modified: bad maxGasreqForFailingOffers");

      assertEq(modified.monitor(),packed.monitor(),"modified: bad monitor");
      assertEq(modified.useOracle(),packed.useOracle(),"modified: bad useOracle");
      assertEq(modified.notify(),packed.notify(),"modified: bad notify");
      assertEq(modified.gasprice(),packed.gasprice(),"modified: bad gasprice");
      assertEq(modified.gasmax(),packed.gasmax(),"modified: bad gasmax");
      assertEq(modified.dead(),packed.dead(),"modified: bad dead");
      assertEq(modified.maxRecursionDepth(),packed.maxRecursionDepth(),"modified: bad maxRecursionDepth");
    }

  function test_unpack(Global packed) public {
    (address monitor, bool useOracle, bool notify, uint gasprice, uint gasmax, bool dead, uint maxRecursionDepth, uint maxGasreqForFailingOffers) = packed.unpack();

    assertEq(packed.monitor(),monitor,"bad monitor");
    assertEq(packed.useOracle(),useOracle,"bad useOracle");
    assertEq(packed.notify(),notify,"bad notify");
    assertEq(packed.gasprice(),gasprice,"bad gasprice");
    assertEq(packed.gasmax(),gasmax,"bad gasmax");
    assertEq(packed.dead(),dead,"bad dead");
    assertEq(packed.maxRecursionDepth(),maxRecursionDepth,"bad maxRecursionDepth");
    assertEq(packed.maxGasreqForFailingOffers(),maxGasreqForFailingOffers,"bad maxGasreqForFailingOffers");
  }

  /* neither of_struct nor to_struct are injective. 
    - of_struct cuts of the high-order bits
    - to_struct removes the information in booleans
    So they're not inverses of each other.
    Instead we test field by field. The getters could be the constant function but no: they are tested in test_pack.
  */

  function test_inverse_1(Global packed) public {
    GlobalUnpacked memory unpacked = packed.to_struct();
    assertEq(unpacked.monitor,packed.monitor(),"bad monitor");
    assertEq(unpacked.useOracle,packed.useOracle(),"bad useOracle");
    assertEq(unpacked.notify,packed.notify(),"bad notify");
    assertEq(unpacked.gasprice,packed.gasprice(),"bad gasprice");
    assertEq(unpacked.gasmax,packed.gasmax(),"bad gasmax");
    assertEq(unpacked.dead,packed.dead(),"bad dead");
    assertEq(unpacked.maxRecursionDepth,packed.maxRecursionDepth(),"bad maxRecursionDepth");
    assertEq(unpacked.maxGasreqForFailingOffers,packed.maxGasreqForFailingOffers(),"bad maxGasreqForFailingOffers");
  }

  function test_inverse_2(GlobalUnpacked memory unpacked) public {
    Global packed = GlobalLib.t_of_struct(unpacked);
    Global packed2;
    packed2 = packed2.monitor(unpacked.monitor);
    packed2 = packed2.useOracle(unpacked.useOracle);
    packed2 = packed2.notify(unpacked.notify);
    packed2 = packed2.gasprice(unpacked.gasprice);
    packed2 = packed2.gasmax(unpacked.gasmax);
    packed2 = packed2.dead(unpacked.dead);
    packed2 = packed2.maxRecursionDepth(unpacked.maxRecursionDepth);
    packed2 = packed2.maxGasreqForFailingOffers(unpacked.maxGasreqForFailingOffers);
    assertEq(packed.monitor(),packed2.monitor(),"bad monitor");
    assertEq(packed.useOracle(),packed2.useOracle(),"bad useOracle");
    assertEq(packed.notify(),packed2.notify(),"bad notify");
    assertEq(packed.gasprice(),packed2.gasprice(),"bad gasprice");
    assertEq(packed.gasmax(),packed2.gasmax(),"bad gasmax");
    assertEq(packed.dead(),packed2.dead(),"bad dead");
    assertEq(packed.maxRecursionDepth(),packed2.maxRecursionDepth(),"bad maxRecursionDepth");
    assertEq(packed.maxGasreqForFailingOffers(),packed2.maxGasreqForFailingOffers(),"bad maxGasreqForFailingOffers");
  }
}
