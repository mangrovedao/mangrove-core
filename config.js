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

/////////////////////////////////////
// mangrove-deployments configuration

// The SemVer range describing the versions of the Mangrove core contracts
// to query mangrove-deployments for.
// Default is the latest patch of the current package version.
const packageVersion = require("./package.json").version;
exports.coreDeploymentVersionRangePattern = `^${packageVersion}`;

// Whether to query mangrove-deployments for released (true), unreleased (false),
// or the latest of either (undefined) versions of the core contracts.
// Default is the latest regardless of their release status.
exports.coreDeploymentVersionReleasedFilter = undefined;
