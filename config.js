// Contracts that should export their ABI only
exports.abi_exports = [
  "Mangrove",
  "MgvReader",
  "MgvCleaner",
  "MgvOracle",
  "SimpleTestMaker",
  "TestToken",
  "IERC20",
  "MangroveOrder",
  "MangroveOrderEnriched",
  "AbstractRouter",
  "AaveDeepRouter",
  "AaveV3Module",
  "ICreditDelegationToken",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = ["SimpleMaker", "MultiMaker"];

// Deployment files that should be distributed, this object is a mapping
// from broadcast directory to the dist/broadcast directory
exports.dist_broadcast_files = {
  "Mumbai.s.sol/80001": "maticmum",
};
