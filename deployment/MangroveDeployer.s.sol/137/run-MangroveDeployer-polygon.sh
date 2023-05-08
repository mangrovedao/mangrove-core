#!/usr/bin/env bash
# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e

source deployment/lib/controlledContractDeploy.sh polygon MangroveDeployer CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000
