#!/usr/bin/env bash
# Runs a Solidity deployment script in a controlled environment, ie. an environment with only the given env vars.
#
# The broadcast log (cleaned for secrets) is stored for later reference and should be comitted to git.
#
# NB: Secrets must not be given as arguments to this script as the command
# The script requires the presence of the following env vars in the environment:
#
#    ${CHAIN_NAME}_PRIVATE_KEY         The private key of the deployer EOA
#    ${CHAIN_NAME}_PRIVATE_ADDRESS     The address of the deployer EOA
#    ${CHAIN_NAME}_NODE_URL            The RPC URL
#    ${CHAIN_NAME}_API_KEY             The API key for the block explorer (Etherscan, PolygonScan, ...)
#
# NB: Requires jq (a JSON processor) to be installed, see https://stedolan.github.io/jq/
#
# Usage:
#   controlledEnvDeploy.sh chain_name deployment_solidity_script ENV_VAR1=value ...
#
#
# Example:
#   controlledEnvDeploy.sh polygon MangroveDeployer CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000


# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
# FIXME: Remove the following line:
set -ex
# set -e

# TODO:
# - Extract logic for secrets to reusable script?
# - Add flags for controlling whether --legacy and --verify are passed to the deployment


# Foundry automatically loads .env, so in order to prevent these secrets from affecting the deployment,
# we temporarily rename .env while the script executes.
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


# Name parameters
SCRIPT_NAME=$(basename $0)
CHAIN_NAME=$1
DEPLOYMENT_SCRIPT=$2
ENV_VAR_ARGUMENTS=${@:3}

# Set internal script vars for secrets, paths, and files
LIB_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${LIB_DIR}/internalScriptVars.sh"

# FIXME: This shouldn't exit when running in verification mode
if [ -f "$DEPLOYMENT_LOG" ]; then
  # The deployment already exists
  echo "Deployment log for this deployment script, chain, and version already exists, exiting"
  echo "  Deployment log: ${DEPLOYMENT_LOG}"
  echo "  Deployment script: ${DEPLOYMENT_SCRIPT}"
  echo "  Chain name: ${CHAIN_NAME}"
  echo "  Chain ID: ${CHAIN_ID}"
  echo "  Package version: ${PACKAGE_VERSION}"
  exit 1
fi


# Run deployment script in a controlled environment:
#
# We use `env -i` to ensure the deploy only uses the listed environment variables, thereby ensuring replicability.
# Approach:
#   1. use SECRET=$SECRET to copy any required _secrets_ to the environment of the deploy command.
#      Secrets must not affect the deployed code as this prevents later verification.
#
#   2. Only copy secrets, all other values should be explicitly stated in ENV_VAR_ARGUMENTS
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
forge script --fork-url $CHAIN_NAME $DEPLOYMENT_SCRIPT -vvv --broadcast --verify --legacy # NB legacy is for some reason needeed for local anvil fork


# Copy broadcast log to deployment log w/o the RPC URL
mkdir -p "${DEPLOYMENT_DIR}"
jq --arg deployCommand "${SCRIPT_NAME} $*" --arg packageVersion "$PACKAGE_VERSION" \
   'del(.transactions[].rpc, .path) | . + { packageVersion: $packageVersion, deployCommand: $deployCommand }' \
   "${BROADCAST_LOG}" >"${DEPLOYMENT_LOG}"
