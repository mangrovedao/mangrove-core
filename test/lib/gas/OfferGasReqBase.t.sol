// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {MangroveTest, MgvReader, TestTaker} from "@mgv/test/lib/MangroveTest.sol";
import {IMangrove} from "@mgv/src/IMangrove.sol";
import {PinnedPolygonFork} from "@mgv/test/lib/forks/Polygon.sol";
import {GenericFork} from "@mgv/test/lib/forks/Generic.sol";
import {OLKey} from "@mgv/src/core/MgvLib.sol";
import {TestToken} from "@mgv/test/lib/tokens/TestToken.sol";
import {GasTestBaseStored} from "./GasTestBase.t.sol";
import {MgvOracle} from "@mgv/src/periphery/MgvOracle.sol";
import {console2} from "@mgv/forge-std/console2.sol";

///@notice base class for creating tests of gasreq for contracts. Probe the `this.getMeasuredGasused` for measured gasreq.
abstract contract OfferGasReqBaseTest is MangroveTest, GasTestBaseStored {
  GenericFork internal fork;
  MgvOracle internal oracle;
  mapping(bytes32 => TestTaker) internal takers;

  function prankTaker(OLKey memory _olKey) internal {
    vm.prank($(takers[_olKey.hash()]));
  }

  function setGasprice(uint _gasprice) internal {
    if (address(oracle) != address(0)) {
      oracle.setGasPrice(_gasprice);
    } else {
      mgv.setGasprice(_gasprice);
    }
  }

  function setUpOptions() internal virtual {
    options.measureGasusedMangrove = true;
  }

  function getStored() internal view override returns (IMangrove, TestTaker, OLKey memory, uint) {
    return (mgv, takers[olKey.hash()], olKey, 0);
  }

  function setUpGeneric() public virtual {
    setUpOptions();
    super.setUp();
    oracle = new MgvOracle({governance_: $(this), initialMutator_: $(this), initialGasPrice_: options.gasprice});
    mgv.setMonitor(address(oracle));
    mgv.setUseOracle(true);
    fork = new GenericFork();
    fork.set(options.base.symbol, $(base));
    fork.set(options.quote.symbol, $(quote));
    description = "generic - gasreq";
  }

  function setUpPolygon() public virtual {
    setUpOptions();
    super.setUp();
    fork = new PinnedPolygonFork(39880000);
    fork.setUp();
    options.gasprice = 90;
    options.gasbase = 200_000;
    options.defaultFee = 30;
    mgv = setupMangrove();
    oracle = new MgvOracle({governance_: $(this), initialMutator_: $(this), initialGasPrice_: options.gasprice});
    mgv.setMonitor(address(oracle));
    mgv.setUseOracle(true);
    reader = new MgvReader($(mgv));
    description = "polygon - gasreq";
  }

  function setUpTokens(string memory baseToken, string memory quoteToken) public virtual {
    description = string.concat(description, " - ", baseToken, "/", quoteToken);
    address baseAddress = fork.get(baseToken);
    address quoteAddress = fork.get(quoteToken);
    base = TestToken(baseAddress);
    quote = TestToken(quoteAddress);
    olKey = OLKey($(base), $(quote), options.defaultTickSpacing);
    lo = OLKey($(quote), $(base), options.defaultTickSpacing);
    setupMarket(olKey);
    setupMarket(lo);

    // Create taker for taking quote
    TestTaker takerLo = setupTaker(lo, "TakerSell");
    takerLo.approveMgv(base, type(uint).max);
    deal($(base), $(takerLo), 200000 ether);
    takers[lo.hash()] = takerLo;

    // Create taker for taking base
    TestTaker takerOl = setupTaker(olKey, "TakerBuy");
    takerOl.approveMgv(quote, type(uint).max);
    deal($(quote), $(takerOl), 200000 ether);
    takers[olKey.hash()] = takerOl;
  }

  /// @notice output the measured gasused for a given posthook in format collectable by gas-measurement.
  function logGasreqAsGasUsed(uint posthookIndex) internal view {
    console2.log("Gas used: %s", getMeasuredGasused(posthookIndex));
  }
}
