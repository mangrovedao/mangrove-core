// Contracts that should export their ABI only
exports.abi_exports = [
  "IMangrove",
  "Mangrove",
  "MgvReader",
  "MgvOracle",
  "TestToken",
  "IERC20",
];

// Contracts that should export their ABI + bytecode
exports.full_exports = ["SimpleTestMaker"];
