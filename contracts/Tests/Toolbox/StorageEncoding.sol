// SPDX-License-Identifier: Unlicense

/* Testing bad storage encoding */

// We can't even encode storage references without the experimental encoder
pragma abicoder v2;

pragma solidity ^0.7.4;
import {Test as TestEvents} from "@giry/hardhat-test-solidity/test.sol";
import "hardhat/console.sol";

contract StorageEncoding {}

struct S {
  uint a;
}

library Lib {
  function a(S storage s) public view {
    s; // silence warning about unused parameter
    console.log("in Lib.a: calldata received");
    console.logBytes(msg.data);
  }
}

contract Failer_Test {
  receive() external payable {}

  function exec() external view {
    console.log("exec");
    require(false);
  }

  function execBig() external view {
    console.log("execBig");
    string memory wtf = new string(100_000);
    require(false, wtf);
  }

  function failed_yul_test() public {
    bytes memory b = new bytes(100_000);
    b;
    uint g0 = gasleft();
    bytes memory cd = abi.encodeWithSelector(this.execBig.selector);
    bytes memory retdata = new bytes(32);
    assembly {
      let success := delegatecall(
        500000,
        address(),
        add(cd, 32),
        4,
        add(retdata, 32),
        0
      )
    }
    console.log("GasUsed: %d", g0 - gasleft());
  }

  function failer_small_test() public {
    uint g0 = gasleft();
    (bool success, bytes memory retdata) = address(this).delegatecall{
      gas: 500_000
    }(abi.encodeWithSelector(this.exec.selector));
    success;
    retdata;
    console.log("GasUsed: %d", g0 - gasleft());
  }

  function failer_big_with_retdata_bytes_test() public {
    bytes memory b = new bytes(100_000);
    b;
    uint g0 = gasleft();
    (bool success, bytes memory retdata) = address(this).delegatecall{
      gas: 500_000
    }(abi.encodeWithSelector(this.execBig.selector));
    success;
    retdata;

    console.log("GasUsed: %d", g0 - gasleft());
  }
}

contract StorageEncoding_Test {
  receive() external payable {}

  S sss; // We add some padding so the storage ref for s is not 0
  S ss;
  S s;

  function _test() public {
    console.log("Lib.a selector:");
    console.logBytes4(Lib.a.selector);
    console.log("___________________");

    console.log("[Encoding s manually]");
    console.log("abi.encodeWithSelector(Lib.a.selector,s)):");
    bytes memory data = abi.encodeWithSelector(Lib.a.selector, s);
    console.logBytes(data);
    console.log("Calling address(Lib).delegatecall(u)...");
    bool success;
    (success, ) = address(Lib).delegatecall(data);
    console.log("___________________");

    console.log("[Encoding s with compiler]");
    console.log("Calling Lib.a(s)...");
    Lib.a(s);
    console.log("___________________");
  }
}

contract Abi_Test {
  receive() external payable {}

  function wordOfBytes(bytes memory data) internal pure returns (bytes32 w) {
    assembly {
      w := mload(add(data, 32))
    }
  }

  function bytesOfWord(bytes32 w) internal pure returns (bytes memory data) {
    data = new bytes(32);
    assembly {
      mstore(add(data, 32), w)
    }
  }

  function wordOfUint(uint x) internal pure returns (bytes32 w) {
    w = bytes32(x);
  }

  enum Arity {
    N,
    U,
    B,
    T
  }
  bytes32 constant MASKHEADER =
    0x00ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff;
  bytes32 constant MASKFIRSTARG =
    0x00000000000000000000000000ffffffffffffffffffffffffffffffffffffff;

  function encode_decode_test() public {
    bytes memory x = abi.encodePacked(
      Arity.B,
      uint96(1 ether),
      uint96(2 ether)
    );
    bytes32 w = wordOfBytes(x);
    console.logBytes32(w);
    console.logBytes32(w >> (31 * 8));
    bytes memory header = bytesOfWord(w >> (31 * 8)); // header is encode in the first byte
    Arity t = abi.decode(header, (Arity));
    TestEvents.check(t == Arity.B, "Incorrect decoding of header");
    bytes memory arg1 = bytesOfWord((w & MASKHEADER) >> (19 * 8));
    console.logBytes(arg1);
    TestEvents.check(
      uint96(1 ether) == abi.decode(arg1, (uint96)),
      "Incorrect decoding of arg1"
    );
    bytes memory arg2 = bytesOfWord((w & MASKFIRSTARG) >> (7 * 8));
    console.logBytes(arg2);
    TestEvents.check(
      uint96(2 ether) == abi.decode(arg2, (uint96)),
      "Incorrect decoding of arg2"
    );
  }
}

// contract EncodeDecode_Test {
//   receive() external payable {}
//   enum T {U,B}

//   function encode(uint192 x) internal view returns (bytes memory){
//     console.log("encoding",uint(x));
//     bytes memory data = new bytes(32);
//     data = abi.encode(T.U,abi.encode(x));
//     console.logBytes(data);
//     return data;
//   }
//   function encode(uint96 x, uint96 y) internal view returns (bytes memory){
//     console.log("encoding",uint(x),uint(y));

//     bytes memory data = new bytes(32);
//     data = abi.encode(T.B,abi.encode(x,y));
//     console.logBytes(data);
//     return data;
//   }

//   function decode(bytes memory data) internal view returns (uint[] memory) {
//     console.log("Decoding");
//     console.logBytes(data);
//     (T t,bytes memory data_) = abi.decode(data,(T,bytes));
//     if (t==T.B) {
//       console.log("Binary predicate detected");
//       uint[] memory args = new uint[](2);
//       (uint96 x, uint96 y) = abi.decode(data_,(uint96,uint96));
//       args[0] = uint(x);
//       args[1] = uint(y);
//       return args;
//     }
//     else{
//       console.log("Unary predicate detected");
//       uint[] memory args = new uint[](1);
//       args[0] = uint(abi.decode(data_,(uint192)));
//       return args;
//     }
//   }

//   function encode_decode(uint x) internal view {
//     bytes memory data = encode(uint192(x));
//     uint[] memory args = decode(data);
//     for (uint i=0;i<args.length;i++){
//       console.log(args[i]);
//     }
//   }

//   function encode_decode(uint x, uint y) internal view {
//     bytes memory data = encode(uint96(x), uint96(y));
//     uint[] memory args = decode(data);
//     for (uint i=0;i<args.length;i++){
//       console.log(args[i]);
//     }
//   }

//   function encode_decode_test() public view {
//     encode_decode(123456789);
//     encode_decode(1234,56789);
//   }

// }
