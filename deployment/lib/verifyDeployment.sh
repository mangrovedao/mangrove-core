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


# NB: set -x prints secrets, so shouldn't be used in anything public like GH actions
# Exit script on error
set -e


# Outline
# 1. Get the contract names and addresses from the deployment log
# 2. Get the lowest block number from the deployment log
#    b. set BLOCKNUMBER=lowest - 1
# 3. Run a local Anvil that forks the chain at BLOCKNUMBER
# 4. For each contract:
#    a. fetch the code from the real chain
#    b. fetch the code from the fork
#    c. compare and throw if different


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
DEPLOYMENT_LIB_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
source "${DEPLOYMENT_LIB_DIR}/internalScriptVars.sh"


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


ANVIL_PORT=8546
ANVIL_URL="http://127.0.0.1:${ANVIL_PORT}"

# NB: This does not work when the chain we're forking is an Anvil fork itself:
#     That Anvil fork ignores the blocknumber in requests and instead returns the latest chain data.
anvil --port $ANVIL_PORT --fork-url ${!CHAIN_NODE_URL_VAR} --fork-block-number $BLOCKNUMBER &
ANVIL_PROCESS_ID=$!

# Wait for Anvil to be ready
sleep 2


# Run deployment against the fork as if it were the real chain
env ${CHAIN_NODE_URL_VAR}="$ANVIL_URL" DEPLOYMENT_VERIFICATION=true $CHAIN_DEPLOYMENT_SCRIPT


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
