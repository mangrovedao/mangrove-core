const contextAddresses = require("@mangrovedao/context-addresses");
const fs = require("fs");
const path = require("path");
const config = require("./config");

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

// This is a hack to get the network names because the addresses
// file names use non-canonical network names from ethers.js
const networkNames = {
  1: "mainnet",
  5: "goerli",
  137: "matic",
  42161: "arbitrum",
  80001: "maticmum",
};

// Construct the addresses object for each network
const contextAddressesByNetwork = {}; // network name => { name: string, address: string }[]
function getOrCreateNetworkAddresses(networkId) {
  const networkName = networkNames[+networkId];
  let networkAddresses = contextAddressesByNetwork[networkName];
  if (networkAddresses === undefined) {
    networkAddresses = [];
    contextAddressesByNetwork[networkName] = networkAddresses;
  }
  return networkAddresses;
}

// Accounts
const allAccounts = contextAddresses.getAllAccounts();
for (const [accountId, account] of Object.entries(allAccounts)) {
  for (const [networkId, address] of Object.entries(account.networkAddresses)) {
    const networkAddresses = getOrCreateNetworkAddresses(networkId);
    networkAddresses.push({
      name: accountId,
      address: address,
    });
  }
}

// Token addresses
const allErc20s = contextAddresses.getAllErc20s();
for (const [erc20Id, erc20] of Object.entries(allErc20s)) {
  for (const [networkId, networkInstances] of Object.entries(
    erc20.networkInstances,
  )) {
    const networkAddresses = getOrCreateNetworkAddresses(networkId);
    for (const [instanceId, networkInstance] of Object.entries(
      networkInstances,
    )) {
      networkAddresses.push({
        name: instanceId,
        address: networkInstance.address,
      });
      // Also register the default instance as the token symbol for convenience
      if (networkInstance.default) {
        networkAddresses.push({
          name: erc20.symbol,
          address: networkInstance.address,
        });
      }
    }
  }
}

// Replace the addresses files with the loaded context addresses
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
