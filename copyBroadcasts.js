/* ***** Mangrove tooling script ********* *
This script copies foundry broadcasts to the distribution directory, according
to the config file.
*/

const shell = require("shelljs");
shell.config.fatal = true; // throw if a command errors
const fs = require("fs");
const path = require("path");
const config = require("./config.js");
const cwd = process.cwd();

const argv = require("yargs").usage("$0").version(false).help().argv;

const sourceDir = path.resolve("./broadcast");
const outDir = path.resolve("./dist/broadcast");

for (const [din, dout] of Object.entries(config.dist_broadcast_files)) {
  const Din = path.join(sourceDir, din);
  const Dout = path.join(outDir, dout);

  // do not delete existing deploys as in copyArtifacts.js, this is supposed to be monotone
  if (fs.existsSync(Din) && fs.statSync(Din).isDirectory()) {
    if (fs.opendirSync(Din).readSync() !== null) {
      // check for empty dir
      shell.cd(Din);
      shell.cp("*", Dout);
      shell.cd("../");
    }
  } else {
    console.log(`No directory ${din}, skipping.`);
  }
}
