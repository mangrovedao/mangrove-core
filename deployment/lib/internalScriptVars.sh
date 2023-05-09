#!/usr/bin/env bash
# Sets variables used by the library scripts based on $CHAIN_NAME and $DEPLOYMENT_LIB_DIR

# Derive name of env vars with chain specific secrets and check that they are set
CHAIN_NAME_UPPER=$(echo "$CHAIN_NAME" | awk '{print toupper($0)}')

CHAIN_PRIVATE_KEY_VAR=${CHAIN_NAME_UPPER}_PRIVATE_KEY
[ -z "${!CHAIN_PRIVATE_KEY_VAR}" ] && echo "$CHAIN_PRIVATE_KEY_VAR has not been set" && exit 1
CHAIN_PRIVATE_ADDRESS_VAR=${CHAIN_NAME_UPPER}_PRIVATE_ADDRESS
[ -z "${!CHAIN_PRIVATE_ADDRESS_VAR}" ] && echo "$CHAIN_PRIVATE_ADDRESS_VAR has not been set" && exit 1
CHAIN_NODE_URL_VAR=${CHAIN_NAME_UPPER}_NODE_URL
[ -z "${!CHAIN_NODE_URL_VAR}" ] && echo "$CHAIN_NODE_URL_VAR has not been set" && exit 1
CHAIN_API_KEY_VAR=${CHAIN_NAME_UPPER}_API_KEY
[ -z "${!CHAIN_API_KEY_VAR}" ] && echo "$CHAIN_API_KEY_VAR has not been set" && exit 1


# Identify directories, files, and arguments
# Structure:
#    $ROOT_DIR
#    ∟ deployment                                   <- $DEPLOYMENT_BASE_DIR
#      ∟ lib                                        <- $DEPLOYMENT_LIB_DIR
#      ∟ logs                                       <- $DEPLOYMENT_LOGS_DIR
#        ∟ $DEPLOYMENT_SCRIPT.s.sol
#          ∟ $CHAIN_ID
#            ∟ $PACKAGE_VERSION                     <- $DEPLOYMENT_DIR
#              ∟ deployment-log.json                <- $DEPLOYMENT_LOG
#      ∟ scripts
#        ∟ $CHAIN_NAME
#          ∟ run-$DEPLOYMENT_SCRIPT-$CHAIN_NAME.sh  <- $CHAIN_DEPLOYMENT_SCRIPT
#    ∟ broadcast                                    <- $BROADCAST_BASE_DIR
#      ∟ $DEPLOYMENT_SCRIPT.s.sol
#        ∟ $CHAIN_ID                                <- $BROADCAST_DIR
#          ∟ run-latest.json                        <- $BROADCAST_LOG
DEPLOYMENT_BASE_DIR=$( dirname "$DEPLOYMENT_LIB_DIR" )
ROOT_DIR=$( dirname "$DEPLOYMENT_BASE_DIR" )

CHAIN_ID=$( cast chain-id --rpc-url "${!CHAIN_NODE_URL_VAR}" )
PACKAGE_VERSION=$( yarn package-version )

BROADCAST_BASE_DIR="${ROOT_DIR}/broadcast/"
BROADCAST_DIR="${BROADCAST_BASE_DIR}/${DEPLOYMENT_SCRIPT}.s.sol/${CHAIN_ID}"
BROADCAST_LOG="${BROADCAST_DIR}/run-latest.json"

DEPLOYMENT_LOGS_DIR="${DEPLOYMENT_BASE_DIR}/logs"
DEPLOYMENT_DIR="${DEPLOYMENT_LOGS_DIR}/${DEPLOYMENT_SCRIPT}.s.sol/${CHAIN_ID}/${PACKAGE_VERSION}"
DEPLOYMENT_LOG="${DEPLOYMENT_DIR}/deployment-log.json"

CHAIN_DEPLOYMENT_SCRIPT="${DEPLOYMENT_BASE_DIR}/scripts/${CHAIN_NAME}/run-${DEPLOYMENT_SCRIPT}-${CHAIN_NAME}.sh"

WRITE_DEPLOY=""
if [ "$DEPLOYMENT_VERIFICATION" == "true" ]
then
  WRITE_DEPLOY=false
else
  WRITE_DEPLOY=true
fi
