#!/usr/bin/env bash
DEPLOYMENT_LIB_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )/../../lib" &> /dev/null && pwd )

"${DEPLOYMENT_LIB_DIR}/controlledEnvDeploy.sh" polygon MangroveDeployer CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000
