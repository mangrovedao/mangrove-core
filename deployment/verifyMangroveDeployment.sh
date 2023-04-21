#!/usr/bin/env bash
# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e

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

ANVIL_PROCESS_ID=""
function finish {
  if [ -f "$DOT_ENV_BACKUP" ]
  then
    # Restore the .env file
    $(mv $DOT_ENV_BACKUP ".env")
    echo ".env restored from $DOT_ENV_BACKUP"
  fi

  if [ ! -z "$ANVIL_PROCESS_ID" ]
  then
    kill $ANVIL_PROCESS_ID
  fi
}
trap finish EXIT

cast code --rpc-url $POLYGON_NODE_URL 0xbd6Cb56f02Ce4d7DaAa507023fA4b797eFBd0D7c >Mangrove-code-on-Polygon.txt
cast code --rpc-url $POLYGON_NODE_URL 0x01C1aD4C493936F21e549b0Ac6f2FB3491c5186f >MgvOracle-code-on-Polygon.txt
cast code --rpc-url $POLYGON_NODE_URL 0xB1904f43c7d6f46d047921B422BAc0e5757E8bDd >MgvReader-code-on-Polygon.txt
cast code --rpc-url $POLYGON_NODE_URL 0x062B6075b7627f3f89d7A43Aa52a204FCcB928Eb >MgvCleaner-code-on-Polygon.txt

anvil --port 8545 --fork-url $POLYGON_NODE_URL & #--fork-block-number 41449558 &
ANVIL_PROCESS_ID=$!


# Wait for Anvil to be ready
sleep 2

# Talk to the local Anvil fork as if it's Polygon
export POLYGON_NODE_URL=$LOCALHOST_URL

# Deploy Mangrove and periphery contracts
# NB: The command used here should be the exact same as the one used to do the real deploy
#     However, due to seom issue (that we don't quite understand) this will/may fail against a local fork, so `--legacy` must be added
WRITE_DEPLOY=true FOUNDRY_OPTIMIZER=true FOUNDRY_OPTIMIZER_RUNS=20000 CHIEF=0x751a02217777b4B85848169A52d6b035D7Cf5DDd GASPRICE=50 GASMAX=1000000 forge script --fork-url polygon MangroveDeployer -vvv --broadcast --legacy

cast code --rpc-url $LOCALHOST_URL 0xbd6Cb56f02Ce4d7DaAa507023fA4b797eFBd0D7c >Mangrove-code-on-fork.txt
if ! cmp -s "Mangrove-code-on-Polygon.txt" "Mangrove-code-on-fork.txt"
then
  echo "Mangrove codes on Polygon and local fork do not match"
  exit 1
fi

cast code --rpc-url $LOCALHOST_URL 0x01C1aD4C493936F21e549b0Ac6f2FB3491c5186f >MgvOracle-code-on-fork.txt
cast code --rpc-url $LOCALHOST_URL 0xB1904f43c7d6f46d047921B422BAc0e5757E8bDd >MgvReader-code-on-fork.txt
cast code --rpc-url $LOCALHOST_URL 0x062B6075b7627f3f89d7A43Aa52a204FCcB928Eb >MgvCleaner-code-on-fork.txt

