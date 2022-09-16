/* ***** Mangrove tooling script ********* *
This script copies foundry broadcasts to the distribution directory, according
to the config file.
*/

const path = require("path");
const shell = require("shelljs");
shell.config.fatal = true; // throw if a command errors

const sourceDir = path.resolve("./addresses");
const outDir = path.resolve("./dist/addresses");

shell.cd(sourceDir);
shell.mkdir("-p", outDir);
shell.rm("-rf", outDir);
shell.cp("-R", sourceDir, outDir);
