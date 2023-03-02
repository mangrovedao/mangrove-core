// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import "mgv_test/lib/MangroveTest.sol";
import "mgv_test/lib/forks/Polygon.sol";
import {ICreditDelegationToken, AaveV3Borrower} from "mgv_src/strategies/integrations/AaveV3Borrower.sol";
import {console} from "forge-std/console.sol";

contract AaveCaller is AaveV3Borrower, MangroveTest {
  constructor(address _addressesProvider, uint borrowMode) AaveV3Borrower(_addressesProvider, 0, borrowMode) {}

  AaveCaller victim;

  function setVictim(AaveCaller c) public {
    victim = c;
  }

  function approveLender(IERC20 token) public {
    _approveLender(token, type(uint).max);
  }

  function supply(IERC20 token, uint amount) public {
    _supply(token, amount, address(this), false);
  }

  function borrow(IERC20 token, uint amount) public {
    _borrow(token, amount, address(this));
  }

  function redeem(IERC20 token, uint amount) public {
    _redeem(token, amount, address(this));
  }

  function executeOperation(address asset, uint amount, uint premium, address, bytes calldata) external returns (bool) {
    approveLender(IERC20(asset));
    deal(asset, address(this), amount + premium);
    console.log(
      "flashloan of %s succeeded, cost is %s %s",
      toUnit(amount, IERC20(asset).decimals()),
      toUnit(premium, IERC20(asset).decimals()),
      IERC20(asset).symbol()
    );
    // checking that victim can no longer redeem its balance
    try victim.redeem(IERC20(asset), overlying(IERC20(asset)).balanceOf(address(victim))) {
      console.log("Attack failed...");
    } catch {
      console.log("Attack succeeded!");
    }
    return true;
  }

  function get_supply(IERC20 asset) public view returns (uint) {
    return asset.balanceOf(address(overlying(asset)));
  }

  function flashloan(IERC20 token, uint amount) public {
    POOL.flashLoanSimple(address(this), address(token), amount, new bytes(0), 0);
  }
}

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
    fork = new PinnedPolygonFork(); // use polygon fork to use dai, usdc and weth addresses
    fork.setUp();

    // use convenience helpers to setup Mangrove
    mgv = setupMangrove();
    reader = new MgvReader($(mgv));

    dai = IERC20(fork.get("DAI"));
    weth = IERC20(fork.get("WETH"));
    usdc = IERC20(fork.get("USDC"));
    v_attacker = new AaveCaller(fork.get("Aave"), 2);
    s_attacker = new AaveCaller(fork.get("Aave"), 1);
    lender = new AaveCaller(fork.get("Aave"), 2);
    v_attacker.setVictim(lender);
    s_attacker.setVictim(lender);
  }

  function dry_pool(IERC20 asset, uint price, bool stable) internal {
    uint dec = asset.decimals();
    deal($(asset), address(lender), 1000 * 10 ** dec);
    lender.approveLender(asset);
    lender.supply(asset, 1000 * 10 ** dec);

    AaveCaller attacker = stable ? s_attacker : v_attacker;
    uint assetSupply = attacker.get_supply(asset);
    // lending on pool to check wether funds can be redeemed during flashloan

    console.log("Asset balance on pool is %s %s", toUnit(assetSupply, dec), asset.symbol());

    // getting enough USDC to dry up the DAI pool
    uint toMint = (assetSupply * price * 130) / 10 ** (dec - 4);
    deal($(usdc), address(attacker), toMint);
    attacker.approveLender(usdc);
    attacker.supply(usdc, toMint);
    (, uint borrowable) = attacker.maxGettableUnderlying(asset, true, address(attacker));
    console.log(
      "* After supplying it to the pool, I could theoretically borrow %s %s", toUnit(borrowable, dec), asset.symbol()
    );
    (, uint borrowCaps) = attacker.getCaps(asset);
    ICreditDelegationToken sdebt = attacker.debtToken(asset, 1);
    ICreditDelegationToken vdebt = attacker.debtToken(asset, 2);
    uint maxBorrowable = borrowCaps == 0 // no borrow cap
      ? assetSupply - (IERC20(address(sdebt)).totalSupply() + IERC20(address(vdebt)).totalSupply())
      : borrowCaps * 10 ** dec - (IERC20(address(sdebt)).totalSupply() + IERC20(address(vdebt)).totalSupply());

    console.log("* Asset borrow cap is:", toUnit(maxBorrowable, dec));
    console.log("* Trying to borrow the whole asset supply...");
    try attacker.borrow(asset, assetSupply) {}
    catch Error(string memory reason) {
      assertEq(reason, "50");
      console.log("Failed: BORROW_CAP_EXCEEDED");
    }

    console.log("* Trying to borrow the asset cap...");
    uint snapshotId = vm.snapshot();
    try attacker.borrow(asset, maxBorrowable) {
      lender.redeem(asset, 1000 * 10 ** dec);
      console.log("Not enough to prevent redeem from lender");
    } catch Error(string memory reason) {
      if (maxBorrowable == 0) {
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
    console.log("* Trying to attack with AAVE flashloan of %s %s", toUnit(assetSupply, dec), asset.symbol());
    attacker.flashloan(asset, assetSupply - 1 ** 10 ** dec);
  }

  function test_dry_pool_dai_stable() public {
    dry_pool(dai, 1, true);
  }

  function test_dry_pool_dai_variable() public {
    dry_pool(dai, 1, false);
  }

  function test_dry_pool_weth_stable() public {
    dry_pool(weth, 1600, true);
  }

  function test_dry_pool_weth_variable() public {
    dry_pool(weth, 1600, false);
  }
}
