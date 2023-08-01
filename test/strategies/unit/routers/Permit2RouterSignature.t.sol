// SPDX-License-Identifier:	AGPL-3.0
pragma solidity ^0.8.10;

import {TestToken} from "mgv_test/lib/tokens/TestToken.sol";
import {MangroveTest} from "mgv_test/lib/MangroveTest.sol";
import {Permit2Router} from "mgv_src/strategies/routers/Permit2Router.sol";
import {ISignatureTransfer} from "lib/permit2/src/interfaces/ISignatureTransfer.sol";
import {IAllowanceTransfer} from "lib/permit2/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "lib/permit2/src/interfaces/IPermit2.sol";
import {DeployPermit2} from "permit2/test/utils/DeployPermit2.sol";
import {Permit2Helpers} from "mgv_test/lib/permit2/permit2Helpers.sol";

contract Permit2RouterSignatureTest is MangroveTest, DeployPermit2, Permit2Helpers {
  address owner;
  uint ownerPrivateKey;
  TestToken weth;
  TestToken usdc;
  uint48 NONCE = 0;

  bytes32 DOMAIN_SEPARATOR;
  uint48 EXPIRATION;
  uint160 AMOUNT = 25;

  Permit2Router router;
  IPermit2 permit2;

  function setUp() public virtual override {
    super.setUp();
    ownerPrivateKey = 0x12341234;
    owner = vm.addr(ownerPrivateKey);

    weth = new TestToken(owner, "WETH", "WETH", 18);
    usdc = new TestToken(owner, "USDC", "USDC", 18);
    permit2 = IPermit2(deployPermit2());
    DOMAIN_SEPARATOR = permit2.DOMAIN_SEPARATOR();

    router = new Permit2Router(permit2);

    EXPIRATION = uint48(block.timestamp + 1000);

    router.bind(address(this));

    deal($(weth), owner, cash(weth, 50));

    vm.startPrank(owner);
    weth.approve(address(permit2), type(uint).max);
    usdc.approve(address(permit2), type(uint).max);
    permit2.approve(address(weth), address(router), type(uint160).max, type(uint48).max);
    permit2.approve(address(usdc), address(router), type(uint160).max, type(uint48).max);
    vm.stopPrank();
  }

  function test_pull_with_signature_transfer() public {
    ISignatureTransfer.PermitTransferFrom memory transferDetails =
      getPermitTransferFrom(address(weth), AMOUNT, NONCE, EXPIRATION);
    bytes memory sig = getPermitTransferSignatureWithSpecifiedAddress(
      transferDetails, ownerPrivateKey, DOMAIN_SEPARATOR, address(router)
    );

    uint startBalanceFrom = weth.balanceOf(owner);
    uint startBalanceTo = weth.balanceOf(address(this));

    router.pull(weth, owner, AMOUNT, true, transferDetails, sig);

    assertEq(weth.balanceOf(owner), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);
  }

  function test_pull_with_permit() public {
    IAllowanceTransfer.PermitSingle memory permit = getPermit(address(weth), AMOUNT, EXPIRATION, NONCE, address(router));
    bytes memory sig = getPermitSignature(permit, ownerPrivateKey, DOMAIN_SEPARATOR);

    uint startBalanceFrom = weth.balanceOf(owner);
    uint startBalanceTo = weth.balanceOf(address(this));

    permit2.permit(owner, permit, sig);
    router.pull(weth, owner, AMOUNT, true);

    assertEq(weth.balanceOf(owner), startBalanceFrom - AMOUNT);
    assertEq(weth.balanceOf(address(this)), startBalanceTo + AMOUNT);
  }
}
