const shell = require("shelljs");
const path = require("path");
shell.config.fatal = true; // throw if a command errors
const here = shell.pwd();
const distAbiDir = process.cwd() + "/dist/mangrove-abis/";
shell.mkdir("-p", distAbiDir);
shell.rm("-rf", path.join(distAbiDir, "*"));
shell.cd("exported-abis/"); // Workaround because shelljs.cp replicates the path to the files (contrary to regular `cp -R`)
shell.cp("-R", "./*", distAbiDir);
shell.cd(here);
// adding true abi export for Mangroveoffer so mangrove.js has deploy code
shell.cd(
  "artifacts/contracts/Strategies/OfferLogics/SingleUser/Deployable/SimpleMaker.sol"
);
shell.cp("./SimpleMaker.json", distAbiDir);
