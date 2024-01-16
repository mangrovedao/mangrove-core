const deployments = require("@mangrovedao/mangrove-deployments");
const fs = require("fs");
const path = require("path");
const config = require("./config");

const script = path.basename(__filename);

if (!config.copyDeployments) {
  console.group(
    "Skipping copying deployments from the mangrove-deployments package.",
  );
  console.log("Set copyDeployments = true in config.js to enable copying.");
  console.log("Using addresses/deployed/*.json files as-is instead.");
  console.groupEnd();
  process.exit(0);
}

console.group(`${script}:`);

// This is a hack to get the network names because the addresses
// file names use non-canonical network names from ethers.js
const networkNames = deployments.mangroveNetworkNames;

// Query deployments based on the configuration in config.js
console.log(
  `Querying mangrove-deployments for core deployments of version ${
    config.coreDeploymentVersionRangePattern
  }, ${
    config.coreDeploymentVersionReleasedFilter === undefined
      ? "released or unreleased"
      : config.coreDeploymentVersionReleasedFilter
        ? "release"
        : "unreleased"
  }...`,
);
const latestCoreDeployments = deployments.getLatestCoreContractsPerNetwork({
  version: config.coreDeploymentVersionRangePattern,
  released: config.coreDeploymentVersionReleasedFilter,
});
console.group(`...found the following deployments of Mangrove:`);
for (const [networkName, namedAddresses] of Object.entries(
  latestCoreDeployments,
)) {
  console.log(
    `${networkName}: ${namedAddresses.mangrove.version} at ${namedAddresses.mangrove.address}`,
  );
}
console.groupEnd();
console.log();

console.log(`Copying deployment addresses...`);

// NB: Test token deployments are included in the context-addresses package,
// so they are not queried from mangrove-deployments.
// Create the addresses files with the loaded deployment addresses
for (const [networkName, namedAddresses] of Object.entries(
  deployments.toNamedAddressesPerNamedNetwork(latestCoreDeployments),
)) {
  const networkAddressesFilePath = path.join(
    __dirname,
    `./addresses/deployed/${networkName}.json`,
  );
  fs.writeFileSync(
    networkAddressesFilePath,
    JSON.stringify(namedAddresses, null, 2),
  );
}

console.log(`...done copying deployment addresses`);
console.groupEnd();
