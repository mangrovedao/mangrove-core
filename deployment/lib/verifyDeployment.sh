#!/usr/bin/env bash
# Verify that a deployment corresponds to the code and deployment script at the current commit.
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
#   verifyDeployment.sh chain_name DEPLOYMENT_SCRIPT
#
#
# Example:
#   verifyDeployment.sh polygon MangroveDeployer

# NB: -x prints secrets, so shouldn't be used in anything public like GH actions
# FIXME: Remove the following line:
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


# Foundry automatically loads .env, so in order to prevent these secrets from affecting the deployment,
# we temporarily rename .env while the script executes.
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


# Name parameters
SCRIPT_NAME=$(basename $0)
CHAIN_NAME=$1
DEPLOYMENT_SCRIPT=$2

# Set internal script vars for secrets, paths, and files
LIB_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${LIB_DIR}/internalScriptVars.sh"


# Get the contracts and addresses 
if [ ! -f "$DEPLOYMENT_LOG" ]; then
  echo "Deployment log not found: $DEPLOYMENT_LOG"
  exit 1
fi
echo "Reading deployment log: $DEPLOYMENT_LOG"

# Creates an array with elements "<tx index>\t<contract name>\t<contract address>"
# Example: CONTRACTS_ARY='([0]="0    Mangrove        0xbd6Cb56f02Ce4d7DaAa507023fA4b797eFBd0D7c" [1]="1      MgvReader       0xB1904f43c7d6f46d047921B422BAc0e5757E8bDd" [2]="2      MgvCleaner    0x062B6075b7627f3f89d7A43Aa52a204FCcB928Eb" [3]="3      MgvOracle       0x01C1aD4C493936F21e549b0Ac6f2FB3491c5186f")'
IFS=$'\n' read -r -d '' -a CONTRACTS_ARY < <(jq -r '[.transactions[]] | to_entries | map(select(.value.transactionType == "CREATE")) | map([.key, .value.contractName, .value.contractAddress]) | .[] | @tsv' ${DEPLOYMENT_LOG} ) || echo ""
if [ ${#CONTRACTS_ARY[@]} -eq 0 ]
then
  echo "  No contracts creations found in deployment log!"
  exit 1
fi
echo "  Found these contract deployments:"
for contract in "${CONTRACTS_ARY[@]}"
do
  echo "    $contract"
done

BLOCKNUMBER_STRING=$( jq -r '[.receipts[].blockNumber] | map(.[2:]) | sort | .[0]' ${DEPLOYMENT_LOG} )
echo "BLOCKNUMBER_STRING: '${BLOCKNUMBER_STRING}'"
BLOCKNUMBER=$(( 16#$BLOCKNUMBER_STRING )) # Convert to decimal
echo "  First block number in deployment: $BLOCKNUMBER"
let "BLOCKNUMBER--"


# TODO:
# 1. [DONE] Get the contract names and addresses from the deployment log
# 2. [DONE] Get the block numbers from the deployment log
#    a. determine the lowest block number
#    b. set BLOCKNUMBER=lowest - 1
# 3. [DONE] Run a local Anvil that forks the chain at BLOCKNUMBER
# 4. For each contract:
#    a. fetch the code from the real chain
#    b. fetch the code from the fork
#    c. compare and throw if different

ANVIL_PORT=8546
ANVIL_URL="http://127.0.0.1:${ANVIL_PORT}"

anvil --port $ANVIL_PORT --fork-url ${!CHAIN_NODE_URL_VAR} --fork-block-number $BLOCKNUMBER &
ANVIL_PROCESS_ID=$!


# Wait for Anvil to be ready
sleep 2

# Run deployment against the fork as if it were the real chain
env ${CHAIN_NODE_URL_VAR}="$ANVIL_URL" $CHAIN_DEPLOYMENT_SCRIPT


echo "Verifying contracts..."
for contract in "${CONTRACTS_ARY[@]}"
do
  IFS=$'\t' read -ra TXINDEX_NAME_ADDRESS <<< "$contract"
  contract_name=${TXINDEX_NAME_ADDRESS[1]}
  contract_address=${TXINDEX_NAME_ADDRESS[2]}
  echo "Verifying contract ${contract_name} at address ${contract_address}"

  CHAIN_CODE=$( mktemp ${contract_name}-${CHAIN_NAME}-code-XXXXXX )
  LOCAL_CODE=$( mktemp ${contract_name}-local-code-XXXXXX )

  cast code --rpc-url "${!CHAIN_NODE_URL_VAR}" $contract_address >"$CHAIN_CODE"
  cast code --rpc-url "$ANVIL_URL" $contract_address >"$LOCAL_CODE"

  if ! cmp -s "$CHAIN_CODE" "$LOCAL_CODE"
  then
    echo "Code for ${contract_name} on ${CHAIN_NAME} does not match local deploy!"
    exit 1
  fi
done

echo "Done, all contracts verified."