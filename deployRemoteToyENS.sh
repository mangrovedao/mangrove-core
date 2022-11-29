#!/usr/bin/env bash
# Create a ToyENS instance on the anvil/hardhat server
# Will use endpoint ETH_RPC_URL or localhost:8545 by default
# Forge scripts that inherit the Deployer contract will automatically deploy a ToyENS
set -xe
TOY_ENS_CODE=$(forge inspect ToyENS deployedBytecode)
cast rpc anvil_setCode 0xdecaf00000000000000000000000000000000000 $TOY_ENS_CODE