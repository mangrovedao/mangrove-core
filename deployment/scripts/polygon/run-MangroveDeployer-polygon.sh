#!/usr/bin/env bash
# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEPLOYMENT_BASE_DIR=$( dirname "$SCRIPT_DIR" )
LIB_DIR="${DEPLOYMENT_BASE_DIR}/lib"
CONTROLLED_ENV_DEPLOY_SCRIPT="${LIB_DIR}/controlledEnvDeploy.sh"

source "$CONTROLLED_ENV_DEPLOY_SCRIPT" polygon MangroveDeployer CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000
