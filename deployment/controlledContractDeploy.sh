#!/usr/bin/env bash
# Usage:
#   controlledContractDeploy.sh chain_name deployment_solidity_script ENV_VAR1=value ...
#
# NB: The scripts provides secrets based on the chain name, so don't set these in the arguments.
#
# Example:
#   controlledContractDeploy.sh polygon MangroveDeployer CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000


# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e


CHAIN_NAME=$1
DEPLOYMENT_SOLIDITY_SCRIPT=$2
ENV_VAR_ARGUMENTS=${@:3}

CHAIN_NAME_UPPER=$(echo "$CHAIN_NAME" | awk '{print toupper($0)}')

CHAIN_PRIVATE_KEY_VAR=${CHAIN_NAME_UPPER}_PRIVATE_KEY
CHAIN_PRIVATE_ADDRESS_VAR=${CHAIN_NAME_UPPER}_PRIVATE_ADDRESS
CHAIN_NODE_URL_VAR=${CHAIN_NAME_UPPER}_NODE_URL
CHAIN_API_KEY_VAR=${CHAIN_NAME_UPPER}_API_KEY

# Foundry automatically loads .env, so we need to circumvent this: We rename it while the script executes.
DOT_ENV_BACKUP=""
if [ -f ".env" ]; then
  # Rename the .env file
  DOT_ENV_BACKUP=$(mktemp .env-backup-XXXXXX)
  $(mv ".env" $DOT_ENV_BACKUP)
  echo ".env renamed temporarily to $DOT_ENV_BACKUP to avoid implicit env vars"
fi

function finish {
  if [ -f "$DOT_ENV_BACKUP" ]
  then
    # Restore the .env file
    $(mv $DOT_ENV_BACKUP ".env")
    echo ".env restored from $DOT_ENV_BACKUP"
  fi
}
trap finish EXIT

# Deploy Mangrove and periphery contracts to Polygon
#
# We use `env -i` to ensure the deploy only uses the listed environment variables, thereby ensuring replicability.
# Rules:
#   1. use `env -i SECRET=$SECRET` to copy any required _secrets_ to the environment of the deploy command.
#      Secrets must not affect the deployed code as this prevents later verification.
#
#   2. Only copy secrets, all other values should be explicitly stated.
#
#   3. `PATH="$PATH"` is needed for forge to be found
#
env -i \
PATH="$PATH" \
${CHAIN_PRIVATE_KEY_VAR}=${!CHAIN_PRIVATE_KEY_VAR} \
${CHAIN_PRIVATE_ADDRESS_VAR}=${!CHAIN_PRIVATE_ADDRESS_VAR} \
${CHAIN_NODE_URL_VAR}=${!CHAIN_NODE_URL_VAR} \
${CHAIN_API_KEY_VAR}=${!CHAIN_API_KEY_VAR} \
WRITE_DEPLOY=true \
$ENV_VAR_ARGUMENTS \
forge script --fork-url $CHAIN_NAME $DEPLOYMENT_SOLIDITY_SCRIPT -vvv --broadcast --verify --legacy # NB legacy is for some reason needeed for local anvil fork

# TODO capture information about the deployment:
# - this file
# - foundry settings?
# - broadcast log
# - verification script? If not generally reusable
# cp "broadcast/$MANGROVE_DEPLOYMENT_SCRIPT.s.sol/137/run-latest.json" TODO
