const shell = require("shelljs");
const path = require("path");

const distAbiDir = process.cwd() + "/dist/mangrove-abis/";
shell.mkdir("-p", distAbiDir);
console.log(path.join(distAbiDir, "*"));
shell.rm("-rf", path.join(distAbiDir, "*"));
shell.cd("build/exported-abis/"); // Workaround because shelljs.cp replicates the path to the files (contrary to regular `cp -R`)
shell.cp("-R", "./*", distAbiDir);
shell.cd("../../");
// adding true abi export for Mangroveoffer so mangrove.js has deploy code
shell.cd(
  "build/cache/solpp-generated-contracts/cache/solpp-generated-contracts/Strategies/OfferLogics/SingleUser/Deployable/SimpleMaker.sol"
);
shell.cp("./SimpleMaker.json", distAbiDir);
