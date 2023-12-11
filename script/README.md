This directory contains scripts (`*.s.sol`) for deploying, configuring, and governing the contracts of the repo.

# Principles for scripts

This is a script example:

```solidity
// SPDX-License-Identifier:	AGPL-3.0
// This script is SmallMgvReaderDeployer.s.sol
pragma solidity ^0.8.13;

import {Mangrove} from "@mgv/src/core/Mangrove.sol";
import {MgvReader} from "@mgv/src/periphery/MgvReader.sol";
import {Deployer} from "@mgv/script/lib/Deployer.sol";
import "@mgv/forge-std/console.sol";

contract SmallMgvReaderDeployer is Deployer {
  TestToken public myToken;

  function run() public {
    innerRun({mgv: Mangrove(envAddressOrName("MGV_GOVERNANCE","MgvGovernance"))});
    outputDeployment();
  }

  function innerRun(Mangrove mgv) public {
    broadcast();
    reader = new MgvReader({mgv: address(mgv)});
    fork.set("MgvReader", address(reader));
  }
}
```

Scripts should follow these principles:

1. They should contain a single `<Contract>` and their filename should be `<Contract>.s.sol`.

2. They should have both a `run` and a `innerRun` function.

   The `run` function is called when the script is called from the command line. This function should only do the following:

   - interpret and validate inputs (eg env vars)
   - call `innerRun`
   - optionally call `outputDeployment`.

   The `innerRun` function should do the actual work of the script. If it calls other scripts, it should call their `innerRun` functions.
   &nbsp;

3. Env vars should be read in the `run` function, not the `innerRun` function.

   This ensures that env vars are only read by the script the user invoked and will not accidentally be picked up (and possibly misinterpreted) by another script.

4. Env vars specifying contracts should always allow either a contract name or an address.

   This is easily achieved by using the `envAddressOrName(envVarName<, optional default address or contract instance name>)` function from `Deployer`.

5. Contract names should be resolved in the `run` function, not the `innerRun` function.

   For instance, you should not write `fork.get("MgvGovernance")` inside an `innerRun` function. Otherwise if your script is called by a "parent" script, it will ignore whatever Mangrove Governance address the user provided.

6. The user should always have the option to specify contract addresses via env vars.

   Instead of always of relying on all addresses being registered in ToyENS and looking these up via hardcoded names, all scripts should allow contract addresses/names to be specified in env vars. This makes the scripts more flexible at no cost.

   This is easily achieved by using the `envAddressOrName(envVarName<, optional default address>)` function from `Deployer`.

7. Specific contract/interface types should be preferred for `innerRun` parameters instead of `address`.

   This reduces the risk of passing a wrong a address from another script.

8. `outputDeployment()` should be called in the `run` function, not in `innerRun`.

   This ensures the outermost script is in control of when the deployment is output.
