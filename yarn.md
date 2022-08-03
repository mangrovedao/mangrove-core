# Yarn usage

⚠️&nbsp; Be aware that when googling Yarn commands, it's often not clear whether the results pertain to Yarn 1 (aka 'Classic') or Yarn 2+. Currently (November 2021), most examples and much tool support is implicitly engineered towards Yarn 1.

## Initial monorepo setup
After first cloning the repo, you should run `yarn install` in the root folder.

```shell
# In ./ or in ./packages/<somePackage>
$ yarn install
```

This
- installs all dependencies in the monorepo
- sets up appropriate symlinks inside the `node_modules` folders of packages that depend on other packages in the monorepo
- installs Husky Git hooks.


NB: Though the `yarn build` (described next) also runs `yarn install`, Yarn fails with an error if `yarn install` has not been run once. So this must be done after cloning. Afterwards `yarn install` should not be required again.


## Update monorepo after clone, pull etc.
Whenever you clone, pull, switch branches or similar, you should run `yarn build` afterwards, either in the root folder or in a package folder:

```shell
# In ./ or in ./packages/<somePackage>
$ yarn build
```

This will 

1. Run `yarn install` which:
    - installs/updates all dependencies in the monorepo
    - updates symlinks inside the `node_modules` folders of packages that depend on other packages in the monorepo
    - updates Husky Git hooks.
2. Build all relevant packages for the folder you're in
    - If you're in root, all packages are built
    - If you're in a package folder, all dependencies of the package and the package itself are built (in topological order).

Your clone is now updated and ready to run :-)


## Building and testing a single package
Mostly, you'll only be working on a single package and don't want to build and test the whole monorepo. You just want to build enough such that the current package can be build, tested, and run.

To do this, change into the package directory:

```shell
$ cd packages/<somePackage>
```

and then run:

```shell
$ yarn build
```

This will update dependencies (using `yarn install`) and recursively build the package and its dependencies in topological order.

To build the package *without updating or building its dependencies*, run

```shell
$ yarn build-this-package
```

To test the package, run

```shell
$ yarn test
```

This will run just the tests in the current package.

If you wish to also run the tests of its dependencies, run

```shell
$ yarn test-with-dependencies
```


## Building and testing all packages
To build all packages, run the following in the root folder:

```shell
$ yarn build
```

Afterwards, if you want to run all tests for all packages, you can run

```shell
$ yarn test
```


## Running scripts in a named package
Regardless of the folder you're in, you can always run a script in a particular package by using the [`yarn workspace <packageName> <commandName>`](https://yarnpkg.com/cli/workspace/#gatsby-focus-wrapper) command. E.g. to run the tests for the `mangrove.js` package, run the following in *any folder*:

```shell
$ yarn workspace @mangrovedao/mangrove.js test
```


## Commands on multiple packages at once
You can use [`yarn workspaces foreach <commandName>`](https://yarnpkg.com/cli/workspaces/foreach) to run a command on all packages.

If the command should be in topological order you can add the flag `--topological-dev`, e.g.:

```shell
$ yarn workspaces foreach --topological-dev build-this-package
```
This will only run `build-this-package` in a package after its dependencies in the monorepo have been built.


## Cleaning build and dist artifacts
Most of the time, running `yarn build` will generate/update the `build` and/or `dist` folders appropriately. However, sometimes the build system gets confused by artifacts left by previous builds. This can for instance happen after refactorings or when switching git branches.
Typical symptoms of this are weird build errors that bear no relation to the changes you've made - or if you've made no changes at all!

In this situation, you can use the `clean` commands, that are symmetric to the `build` commands:

```shell
yarn clean
```

will clean the current package and its dependencies (if run in a package) or all packages if run in root.

```shell
yarn clean-this-package
```
will clean just the current package.


# Packages
Packages should be placed in their own folder under `packages/` and should be structured as regular npm packages.

Each package should have its own `package.json` file based on the following template (though comments should be removed):

```jsonc
{
  "name": "@mangrovedao/<packageName>",                // All packages should be scoped with @mangrovedao.
  "version": "0.0.1",
  "author": "Mangrove DAO",
  "description": "<description of the package>",
  "license": "<license>",                       // License should be chosen appropriately for the specific package.
  "scripts": {
    "precommit": "lint-staged",                 // This script is called by the Husky precommit Git hook.
                                                // We typically use this to autoformat all staged files with `lint-staged`:
                                                // lint-staged runs the command specified in the lint-staged section below
                                                // on the files staged for commit.
    "prepack": "yarn build",                    // Yarn 2 recommends using the `prepack` lifecycle script for building.
    "lint": "eslint . --ext .js,.jsx,.ts,.tsx", // Linting of the specified file types.
    "build-this-package": "<build command(s)>", // This script should build just this package.
                                                // It will be called by `build` scripts whenever this package should be build.
    "build": "yarn install && yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run build-this-package",
                                                // Update and build dependencies and this package in topological order.
    "clean-this-package": "<clean commmand(s)>",// This script should clean just this package.
                                                // It will be called by `clean` scripts whenever this package should be cleaned.
    "clean": "yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run clean-this-package",
                                                // Clean dependencies and this package in topological order.
    "test-with-dependencies": "yarn workspaces foreach -vpiR --topological-dev --from $npm_package_name run test",
                                                // Test this package and its dependencies in topological order.
    "test": "<test command(s)>"                 // This script should test just this package.
                                                // It will be called by the `test` script in root and by `test-with-dependencies`
                                                // whenever this package should be testet.
  },
  "lint-staged": {
    "**/*": "prettier --write --ignore-unknown" // The command that `lint-staged` will run on staged
                                                // files as part of the Husky precommit Git hook.
                                                // `prettier` will autoformat the files which we generally prefer.
  },
  "dependencies": {
    "@mangrovedao/mangrove.js": "workspace:*"          // This is an example of a run-time dependency to another package in the monorepo
  },
  "devDependencies": {
    "@mangrovedao/mangrove-solidity": "workspace:*",   // This is an example of a build-time dependency to another package in the monorepo

    "eslint": "^7.32.0",                        // You probably want this and the following development dependencies
    "eslint-config-prettier": "^8.3.0",         // (the version patterns will probably soon be outdated...):
    "eslint-plugin-prettier": "^4.0.0",
    "lint-staged": "^11.1.2",
    "prettier": "2.3.2",
    "prettier-eslint": "^13.0.0",
    "rimraf": "^3.0.2"                          // Cross-platform tool for deleting folders - useful for cleaning.
  }
}
```


## Dependencies inside monorepo
When adding dependencies to another package in the monorepo, you can use `workspace:*` as the version range, e.g.:

```json
"@mangrovedao/mangrove.js": "workspace:*"
```

Yarn will resolve this dependency amongst the packages in the monorepo and will use a symlink in `node_modules` for the package. You can add dependencies as either run-time dependencies, in `"dependencies"` or as a build-time dependency, in `"devDependencies"`.

When publishing (using e.g. `yarn pack` or `yarn npm publish`) Yarn will replace the version range with the current version of the dependency.

There are more options and details which are documented in the Yarn 2 documentation of workspaces: https://yarnpkg.com/features/workspaces .


## Scripts
A few things are important to note regarding `package.json` scripts:

### Lifecycle scripts and Yarn 2
Yarn 2 deliberately only supports a subset of the lifecycle scripts supported by npm. So when adding/modifying lifecycle scripts, you should consult Yarn 2's documentation on the subject: https://yarnpkg.com/advanced/lifecycle-scripts#gatsby-focus-wrapper .


### `yarn build` VS `yarn install`
A single command should be sufficient for getting a usable repo after updating your clone (e.g. `git clone/pull/merge/...`).

By "usable repo" we mean:
- Internal + external dependencies should be up-to-date
- The packages relevant to *your* work are built and ready to run.

Often this is achieved by having a `postinstall` script which runs any required build steps.

If we added such a `postinstall` script to all packages, a single `yarn install` in root or package would both update dependencies and build the packages you care about.

However, there's an issue with this approach: `postinstall` will also be run when other people install our packages. Thus they would also be forced to build the package and `devDependencies` would have to be changed into `dependencies`.

This is why we've opted to instead add `yarn install` to the `build` scripts in root and in all packages.

This allows us to run a single `yarn build` in root or package to both update dependencies and build the packages you care about.

Note however, that due to a Yarn limitation, one must run `yarn install` after cloning. Otherwise, Yarn will fail when running `yarn build` even though the first action of that command is to run `yarn install`.


# Yarn configuration
Yarn 2 is configured in two places:

- `package.json`: The `workspaces` section tells Yarn which folders should be considered packages/workspaces.
- `.yarnrc.yml`: Configuration of Yarn's internal settings, see https://yarnpkg.com/configuration/yarnrc

A few notes on the reasons for our chosen Yarn 2 configuration:


## `nmHoistingLimits: workspaces`
By default, Yarn hoists dependencies to the highest possible level. However, Hardhat only allows local installs and thus does not support hoisting: https://hardhat.org/errors/#HH12 .

In Yarn 1 (and Lerna) one can prevent hoisting of specific packages, but that's not possible with Yarn 2. We have therefore disabled hoisting past workspaces, i.e., dependencies are always installed in the local `node_modules` folder.


## `nodeLinker: node-modules`
Yarn 2 has introduced an alternative to `node_modules` called "Plug'n'Play". While it sounds promising, it's not fully supported by the ecosystem and we have therefore opted to use the old approach using `node_modules`.
