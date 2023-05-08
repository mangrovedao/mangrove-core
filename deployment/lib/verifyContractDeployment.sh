#!/usr/bin/env bash
# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
set -ex
# set -e

# NOTES:
# - We should call the chain-specific deployment script
#   - If we use a naming convention for those scripts (or folder structure) this should be derivable from (chain name, deploy script name)
# 

# TODO:
# - take chain name and Solidity deployment script name as argument
# - make secrets parametric in chain like in controlledContractDeployment
# - find way to identify the contracts that have been deployed
#   - we can read this from the broadcast log, right?
#   - we can identify CREATE transactions
#          "transactions": [
    # {
    #   "hash": "0x253f9ca88175937f93a23101f82eb8c6bca0e2a1066ebebf4ba742022395848a",
    #   "transactionType": "CREATE",
    #   "contractName": "Mangrove",
    #   "contractAddress": "0x53e805542C3DE1718B3dA4C178b8533172aC76b0",
    #   "function": null,
    #   "arguments": [
    #     "0x751a02217777b4B85848169A52d6b035D7Cf5DDd",
    #     "50",
    #     "1000000"
    #   ],
    #   "rpc": "http://127.0.0.1:8545",
    #   "transaction": {
    #     "type": "0x00",
    #     "from": "0x5902976b1970d65c06a5c748cf28ba8b4373482d",
    #     "gas": "0x5a9f6f",
    #     "value": "0x0",
    #     "data": <removed>
    #     "nonce": "0x4"
    #   },
    #   "additionalContracts": [],
    #   "isFixedGasLimit": false

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
DEPLOYMENT_BASE_DIR=$( dirname "$SCRIPT_DIR" )

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
# FIXME: derive the deployment script to run
source deployment/MangroveDeployer.s.sol/137/run-MangroveDeployer-polygon.sh

cast code --rpc-url $LOCALHOST_URL 0xbd6Cb56f02Ce4d7DaAa507023fA4b797eFBd0D7c >Mangrove-code-on-fork.txt
if ! cmp -s "Mangrove-code-on-Polygon.txt" "Mangrove-code-on-fork.txt"
then
  echo "Mangrove codes on Polygon and local fork do not match"
  exit 1
fi

cast code --rpc-url $LOCALHOST_URL 0x01C1aD4C493936F21e549b0Ac6f2FB3491c5186f >MgvOracle-code-on-fork.txt
cast code --rpc-url $LOCALHOST_URL 0xB1904f43c7d6f46d047921B422BAc0e5757E8bDd >MgvReader-code-on-fork.txt
cast code --rpc-url $LOCALHOST_URL 0x062B6075b7627f3f89d7A43Aa52a204FCcB928Eb >MgvCleaner-code-on-fork.txt

