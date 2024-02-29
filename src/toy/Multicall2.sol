pragma solidity >=0.5.0;
pragma experimental ABIEncoderV2;

/// @title Multicall2 - Aggregate results from multiple read-only function calls
/// @author Michael Elliot <mike@makerdao.com>
/// @author Joshua Levine <joshua@makerdao.com>
/// @author Nick Johnson <arachnid@notdot.net>

contract Multicall2 {
  struct Call {
    address target;
    bytes callData;
  }

  struct Result {
    bool success;
    bytes returnData;
  }

  function aggregate(Call[] memory calls) public returns (uint blockNumber, bytes[] memory returnData) {
    blockNumber = block.number;
    returnData = new bytes[](calls.length);
    for (uint i = 0; i < calls.length; i++) {
      (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);
      require(success, "Multicall aggregate: call failed");
      returnData[i] = ret;
    }
  }

  function blockAndAggregate(Call[] memory calls)
    public
    returns (uint blockNumber, bytes32 blockHash, Result[] memory returnData)
  {
    (blockNumber, blockHash, returnData) = tryBlockAndAggregate(true, calls);
  }

  function getBlockHash(uint blockNumber) public view returns (bytes32 blockHash) {
    blockHash = blockhash(blockNumber);
  }

  function getBlockNumber() public view returns (uint blockNumber) {
    blockNumber = block.number;
  }

  function getCurrentBlockCoinbase() public view returns (address coinbase) {
    coinbase = block.coinbase;
  }

  function getCurrentBlockDifficulty() public view returns (uint difficulty) {
    difficulty = block.difficulty;
  }

  function getCurrentBlockGasLimit() public view returns (uint gaslimit) {
    gaslimit = block.gaslimit;
  }

  function getCurrentBlockTimestamp() public view returns (uint timestamp) {
    timestamp = block.timestamp;
  }

  function getEthBalance(address addr) public view returns (uint balance) {
    balance = addr.balance;
  }

  function getLastBlockHash() public view returns (bytes32 blockHash) {
    blockHash = blockhash(block.number - 1);
  }

  function tryAggregate(bool requireSuccess, Call[] memory calls) public returns (Result[] memory returnData) {
    returnData = new Result[](calls.length);
    for (uint i = 0; i < calls.length; i++) {
      (bool success, bytes memory ret) = calls[i].target.call(calls[i].callData);

      if (requireSuccess) {
        require(success, "Multicall2 aggregate: call failed");
      }

      returnData[i] = Result(success, ret);
    }
  }

  function tryBlockAndAggregate(bool requireSuccess, Call[] memory calls)
    public
    returns (uint blockNumber, bytes32 blockHash, Result[] memory returnData)
  {
    blockNumber = block.number;
    blockHash = blockhash(block.number);
    returnData = tryAggregate(requireSuccess, calls);
  }
}
