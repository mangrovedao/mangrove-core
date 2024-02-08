const contextAddresses = require("@mangrovedao/context-addresses");
const fs = require("fs");
const path = require("path");
const config = require("./config");

const script = path.basename(__filename);

if (!config.copyContextAddresses) {
  console.group(
    "Skipping copying context addresses from the context-addresses package.",
  );
  console.log(
    "Set copyContextAddresses = true in config.js to enable copying.",
  );
  console.log("Using addresses/context/*.json files as-is instead.");
  console.groupEnd();
  process.exit(0);
}

console.log(`${script}: Copying context addresses...`);

// Construct the addresses object for each network
const contextAddressesByNetwork = {}; // network name => { name: string, address: string }[]
function getOrCreateNetworkAddresses(networkName) {
  let networkAddresses = contextAddressesByNetwork[networkName];
  if (networkAddresses === undefined) {
    networkAddresses = contextAddressesByNetwork[networkName] = [];
  }
  return networkAddresses;
}

// Accounts
const allAccounts = contextAddresses.getAllAccounts();
for (const [networkName, namedAddresses] of Object.entries(
  contextAddresses.toNamedAddressesPerNamedNetwork(allAccounts),
)) {
  const networkAddresses = getOrCreateNetworkAddresses(networkName);
  networkAddresses.push(...namedAddresses);
}

// Token addresses
const allErc20s = contextAddresses.getAllErc20s();
const allErc20InstancesPerNamedNetwork =
  contextAddresses.toErc20InstancesPerNamedNetwork(allErc20s);
for (const [networkName, erc20Instances] of Object.entries(
  allErc20InstancesPerNamedNetwork,
)) {
  const networkAddresses = getOrCreateNetworkAddresses(networkName);
  for (const { id, address } of erc20Instances) {
    networkAddresses.push({
      name: id,
      address,
    });
  }
}

// Create the addresses files with the loaded context addresses
for (const networkName in contextAddressesByNetwork) {
  let addressesToWrite = contextAddressesByNetwork[networkName];
  const networkAddressesFilePath = path.join(
    __dirname,
    `./addresses/context/${networkName}.json`,
  );
  fs.writeFileSync(
    networkAddressesFilePath,
    JSON.stringify(addressesToWrite, null, 2),
  );
}

console.log(`${script}: ...Done copying context addresses`);
