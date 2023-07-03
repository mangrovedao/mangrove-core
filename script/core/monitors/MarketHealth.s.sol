// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.13;

import {Deployer} from "mgv_script/lib/Deployer.sol";
import {Test2, console2 as console} from "mgv_lib/Test2.sol";
import {UpdateMarket} from "mgv_script/periphery/UpdateMarket.s.sol";
import {MgvReader, VolumeData, IMangrove} from "mgv_src/periphery/MgvReader.sol";
import {IERC20} from "mgv_src/IERC20.sol";
import {MgvStructs} from "mgv_src/MgvLib.sol";

/**
 * @notice Script to obtain data about a given mangrove half book
 * @notice environment variables that control the script are:
 * @param FILENAME the base name of the files in which data are outputted.
 * <FILENAME>.static for published values (volume and density as promised by makers)
 * <FILENAME>.dynamic for experimental values obtained by running market orders
 * @param VOLUME the amount of outbound token that are required from the market
 * @param TKN_IN the inbound token (token that are sent by the tester)
 * @param TKN_OUT the outbound token (token that are required by the tester)
 */
/**
 * Usage: testing status of buy orders on the WMATIC,USDT market for volumes of up to 100,000 WMATIC (display units)
 *  FILENAME=marketHealth VOLUME=$(cast ff 18 100000) TKN_IN=USDT TKN_OUT=WMATIC \
 *  forge script --fork-url mumbai MarketHealth
 */
contract MarketHealth is Test2, Deployer {
  // needed if some offer fail, in order to receive bounty
  receive() external payable {}

  function run() public {
    IERC20 inbTkn = IERC20(envAddressOrName("TKN_IN"));
    // dealing hopefully enough inbound token to execute a market order
    deal(address(inbTkn), address(this), 10_000_000 * 10 ** inbTkn.decimals());
    string memory filename;
    try vm.envString("FILENAME") returns (string memory name) {
      filename = name;
    } catch {
      filename = "marketData";
    }
    innerRun({
      mgv: IMangrove(envAddressOrName("MGV", "Mangrove")),
      reader: MgvReader(envAddressOrName("MGV_READER", "MgvReader")),
      inbTkn: inbTkn,
      outTkn: IERC20(envAddressOrName("TKN_OUT")),
      outboundTknVolume: vm.envUint("VOLUME"),
      basename: filename
    });
  }

  struct HeapVars {
    uint outDecimals;
    uint inbDecimals;
    uint required;
    VolumeData[] data;
    uint got;
    uint snipesGot;
    uint gave;
    uint snipesGave;
    uint successes;
    uint snipesSuccesses;
    uint failures;
    uint collected;
    uint snipesBounty;
    uint gasreq;
    string filename;
    uint gasbase;
    uint best;
    uint takerWants;
  }

  function innerRun(
    IMangrove mgv,
    MgvReader reader,
    IERC20 inbTkn,
    IERC20 outTkn,
    uint outboundTknVolume,
    string memory basename
  ) public {
    HeapVars memory vars;
    vars.data =
      reader.marketOrder(address(outTkn), address(inbTkn), outboundTknVolume, inbTkn.balanceOf(address(this)), true);
    vars.outDecimals = outTkn.decimals();
    vars.inbDecimals = inbTkn.decimals();
    vars.filename = string.concat(basename, ".static");
    // removing previous data if present
    try vm.removeFile(vars.filename) {} catch {}

    vm.writeLine(vars.filename, "# volume_in volume_out sum_gasreq");
    for (uint i; i < vars.data.length; i++) {
      if (vars.data[i].totalGot <= outboundTknVolume) {
        vars.required = vars.data[i].totalGave;
      }
      vm.writeLine(
        vars.filename,
        string.concat(
          " ",
          toUnit(vars.data[i].totalGave, vars.inbDecimals),
          " ",
          toUnit(vars.data[i].totalGot, vars.outDecimals),
          " ",
          vm.toString(vars.data[i].totalGasreq)
        )
      );
    }
    // minting enough token to get `outboundTknVolume` (*2 in case some offer fail)
    deal(address(inbTkn), address(this), vars.required * 2);
    inbTkn.approve(address(mgv), type(uint).max);

    vars.filename = string.concat(basename, ".dynamic");
    try vm.removeFile(vars.filename) {} catch {}
    vm.writeLine(vars.filename, "# successes failures volume_in volume_out sum_bounty sum_effective_gasreq");

    (, MgvStructs.LocalPacked local) = mgv.config(address(outTkn), address(inbTkn));
    vars.gasbase = local.offer_gasbase();
    uint snapshotId = vm.snapshot();
    while (vars.got < outboundTknVolume) {
      vars.best = mgv.best(address(outTkn), address(inbTkn));
      if (vars.best == 0) {
        break;
      }
      MgvStructs.OfferPacked offer = mgv.offers(address(outTkn), address(inbTkn), vars.best);
      uint[4][] memory targets = new uint256[4][](1);
      vars.takerWants = offer.gives() + vars.got > outboundTknVolume ? outboundTknVolume - vars.got : offer.gives();
      // offering a better price than what the offer requires
      targets[0] = [vars.best, vars.takerWants, offer.wants(), type(uint).max];
      _gas();
      (vars.snipesSuccesses, vars.snipesGot, vars.snipesGave, vars.snipesBounty,) =
        mgv.snipes(address(outTkn), address(inbTkn), targets, true);
      uint g = gas_(true);
      // substracting the empirical overhead of running snipe vs market order
      vars.gasreq += g - 30_000; // vars.gasbase < g ? g - vars.gasbase : 0;
      vars.successes += vars.snipesSuccesses;
      vars.failures = vars.snipesSuccesses == 0 ? vars.failures + 1 : vars.failures;
      vars.got += vars.snipesGot;
      vars.gave += vars.snipesGave;
      vars.collected += vars.snipesBounty;
      vm.writeLine(
        vars.filename,
        string.concat(
          " ",
          vm.toString(vars.successes),
          " ",
          vm.toString(vars.failures),
          " ",
          toUnit(vars.gave, vars.inbDecimals),
          " ",
          toUnit(vars.got, vars.outDecimals),
          " ",
          toUnit(vars.collected, 18),
          " ",
          vm.toString(vars.gasreq)
        )
      );
    }
    require(vm.revertTo(snapshotId), "snapshot restore failed");
    _gas();
    mgv.marketOrder(address(outTkn), address(inbTkn), outboundTknVolume, type(uint160).max, true);
    vars.gasreq = gas_(true);
    vm.writeLine(vars.filename, string.concat("# MarketOrder gas cost: ", vm.toString(vars.gasreq)));
  }
}
