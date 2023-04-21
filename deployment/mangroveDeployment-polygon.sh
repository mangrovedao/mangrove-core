#!/usr/bin/env bash
# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e

MANGROVE_DEPLOYMENT_SCRIPT=MangroveDeployer
CHAIN_NAME=polygon
CHAIN_NUMBER


# Loading .env means we don't know which secrets were used, so should probably be avoided and replaced by explicitly making
# env vars available, eg using `env -i VAR1="$VAR1" command`
# DON'T DO THIS: source .env

# Foundry automatically loads .env, so we need to circumvent this
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
env -i \
PATH="$PATH" \
POLYGON_PRIVATE_KEY=$POLYGON_PRIVATE_KEY \
POLYGON_PRIVATE_ADDRESS=$POLYGON_PRIVATE_ADDRESS \
POLYGON_NODE_URL=$POLYGON_NODE_URL \
POLYGON_API_KEY=$POLYGON_API_KEY \
WRITE_DEPLOY=true \
FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000 \
CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd \
GASPRICE=50 GASMAX=1000000 \
forge script --fork-url polygon $MANGROVE_DEPLOYMENT_SCRIPT -vvv --broadcast --verify --legacy # NB legacy is for some reason needeed for local anvil fork

# TODO capture information about the deployment:
# - this file
# - foundry settings?
# - broadcast log
# - verification script? If not generally reusable
# cp "broadcast/$MANGROVE_DEPLOYMENT_SCRIPT.s.sol/137/run-latest.json" TODO
