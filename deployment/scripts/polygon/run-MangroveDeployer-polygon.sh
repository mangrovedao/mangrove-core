#!/usr/bin/env bash
DEPLOYMENT_LIB_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../../lib" &> /dev/null && pwd )

"${DEPLOYMENT_LIB_DIR}/controlledEnvDeploy.sh" polygon MangroveDeployer CHIEF=0x59a424169526ECae25856038598F862043DCeDf7 GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000
