const deployments = require("@mangrovedao/mangrove-deployments");

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

// Whether to fetch deployments from mangrove-deployments.
// Setting this to false allows manually specifying the addresses to use
// by writing them to the JSON files in the addresses/deployed directory.
// This may be useful if one wants to use a non-primary deployment.
// Default is true.
exports.copyDeployments = true;

// The SemVer range describing the versions of the Mangrove core contracts
// to query mangrove-deployments for.
// Default is the latest patch of the current package version.
const packageVersion = require("./package.json").version;
exports.coreDeploymentVersionRangePattern =
  deployments.createContractVersionPattern(packageVersion);

// Whether to query mangrove-deployments for released (true), unreleased (false),
// or the latest of either (undefined) versions of the core contracts.
// Default is the latest regardless of their release status.
exports.coreDeploymentVersionReleasedFilter = undefined;

//////////////////////////////////
// context-addresses configuration

// Whether to fetch deployments from context-addresses.
// Setting this to false allows manually specifying the addresses to use
// by writing them to the JSON files in the addresses/context directory.
// Default is true.
exports.copyContextAddresses = true;
