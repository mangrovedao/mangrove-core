// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {ICreditDelegationToken, AaveV3Borrower} from "mgv_src/strategies/integrations/AaveV3Borrower.sol";
import {AaveCaller, console} from "mgv_test/lib/agents/AaveCaller.sol";

contract AaveMakerTest is MangroveTest {
  IERC20 weth;
  IERC20 dai;
  IERC20 usdc;

  PolygonFork fork;

  address payable taker;
  AaveCaller s_attacker;
  AaveCaller v_attacker;
  AaveCaller lender;

  receive() external payable virtual {}

  function setUp() public override {
    // use the pinned Polygon fork
    fork = new PinnedPolygonFork(39880000); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();

    dai = IERC20(fork.get("DAI"));
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));
    v_attacker = new AaveCaller(fork.get("AaveAddressProvider"), 2);
    s_attacker = new AaveCaller(fork.get("AaveAddressProvider"), 1);
    lender = new AaveCaller(fork.get("AaveAddressProvider"), 2);
  }

  struct HeapVars {
    uint assetDecimals;
    string assetSymbol;
    uint collateralDecimals;
    string collateralSymbol;
    AaveCaller attacker;
    uint assetSupply;
    uint toMint;
    uint borrowCaps;
    uint maxBorrowable;
    uint borrowable;
    ICreditDelegationToken sdebt;
    ICreditDelegationToken vdebt;
  }

  function dry_pool(IERC20 asset, IERC20 collateral, uint price, bool stable) internal {
    HeapVars memory vars;
    vars.assetDecimals = asset.decimals();
    vars.assetSymbol = asset.symbol();
    vars.collateralDecimals = collateral.decimals();
    vars.collateralSymbol = collateral.symbol();

    deal($(asset), address(lender), 1000 * 10 ** vars.assetDecimals);
    lender.approveLender(asset);
    lender.supply(asset, 1000 * 10 ** vars.assetDecimals);

    vars.attacker = stable ? s_attacker : v_attacker;
    vars.assetSupply = vars.attacker.get_supply(asset);
    // lending on pool to check wether funds can be redeemed during flashloan

    console.log("Asset balance on pool is %s %s", toFixed(vars.assetSupply, vars.assetDecimals), vars.assetSymbol);

    // getting enough USDC to dry up the DAI pool
    if (vars.assetDecimals >= vars.collateralDecimals) {
      vars.toMint = (vars.assetSupply * price * 150) / 10 ** (vars.assetDecimals - (vars.collateralDecimals - 2));
    } else {
      vars.toMint = (vars.assetSupply * price * 150) * 10 ** (vars.collateralDecimals - vars.assetDecimals) / 10 ** 2;
    }
    deal($(collateral), address(vars.attacker), vars.toMint);
    console.log("* Minting %s %s of collateral", toFixed(vars.toMint, vars.collateralDecimals), collateral.symbol());
    vars.attacker.approveLender(collateral);
    vars.attacker.supply(collateral, vars.toMint);
    (, vars.borrowable) = vars.attacker.maxGettableUnderlying(asset, true, address(vars.attacker));
    console.log(
      "* After supplying it to the pool, I could theoretically borrow %s %s",
      toFixed(vars.borrowable, vars.assetDecimals),
      vars.assetSymbol
    );
    (, vars.borrowCaps) = vars.attacker.getCaps(asset);
    ICreditDelegationToken sdebt = vars.attacker.debtToken(asset, 1);
    ICreditDelegationToken vdebt = vars.attacker.debtToken(asset, 2);
    vars.maxBorrowable = vars.borrowCaps == 0 // no borrow cap
      ? vars.assetSupply - (IERC20(address(sdebt)).totalSupply() + IERC20(address(vdebt)).totalSupply())
      : vars.borrowCaps * 10 ** vars.assetDecimals
        - (IERC20(address(sdebt)).totalSupply() + IERC20(address(vdebt)).totalSupply());

    console.log("* Asset borrow cap is:", toFixed(vars.maxBorrowable, vars.assetDecimals));
    console.log("* Trying to borrow more than the cap...");
    try vars.attacker.borrow(asset, vars.maxBorrowable + 1) {}
    catch Error(string memory reason) {
      assertEq(reason, "50");
      console.log("Failed: BORROW_CAP_EXCEEDED");
    }

    console.log("* Trying to borrow maximum borrowable...");
    uint snapshotId = vm.snapshot();
    uint tryBorrow = vars.maxBorrowable > vars.assetSupply ? vars.assetSupply : vars.maxBorrowable;

    try vars.attacker.borrow(asset, tryBorrow) {
      try lender.redeem(asset, 1000 * 10 ** vars.assetDecimals) {
        console.log("Not enough to prevent redeem from lender");
      } catch {
        console.log("attack succeeded!");
        try vars.attacker.repay(asset, tryBorrow) {}
        catch Error(string memory reason) {
          assertEq(reason, "48"); // REPAY AND BORROW not allowed in the same block
          console.log("But repay failed because of old version of Aave...");
        }
      }
    } catch Error(string memory reason) {
      if (vars.maxBorrowable == 0) {
        assertEq(reason, "26");
        console.log("Failed: can borrow 0");
      } else {
        if (bytes32(bytes(reason)) == "31") {
          console.log("Failed: STABLE_BORROWING_NOT_ENABLED");
        } else {
          assertEq(reason, "38");
          console.log("Failed: AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE");
        }
      }
    }
    require(vm.revertTo(snapshotId), "snapshot restore failed");
    console.log(
      "* Trying to attack with AAVE flashloan of %s %s", toFixed(vars.assetSupply, vars.assetDecimals), vars.assetSymbol
    );
    bytes memory cd =
      abi.encodeWithSelector(this.executeAttack.selector, address(lender), asset, 1000 * 10 ** vars.assetDecimals);
    vars.attacker.setCallbackAddress(address(this));
    try vars.attacker.flashloan(asset, vars.assetSupply - 1 ** 10 ** vars.assetDecimals, cd) {
      console.log("Attack succeeded");
      assertTrue(true, "Flashloan attack succeeded");
    } catch {
      assertTrue(false, "Flashloan attack failed");
    }
  }

  function executeAttack(address payable victim, IERC20 asset, uint amount) external {
    console.log("reached");
    try AaveCaller(victim).redeem(asset, amount) {
      console.log("weird");
      require(false, "attack failed"); // if victim can redeem we throw
    } catch {
      console.log("success");
      return;
    }
  }

  function test_dry_pool_dai_stable() public {
    dry_pool(dai, usdc, 1, true);
  }

  function test_dry_pool_dai_variable() public {
    dry_pool(dai, usdc, 1, false);
  }

  function test_dry_pool_weth_stable() public {
    dry_pool(weth, usdc, 1600, true);
  }

  function test_dry_pool_weth_variable() public {
    dry_pool(weth, usdc, 1600, false);
  }

  function test_dry_pool_usdc_stable() public {
    dry_pool(usdc, dai, 1, true);
  }

  function test_dry_pool_usdc_variable() public {
    dry_pool(usdc, dai, 1, false);
  }
}
