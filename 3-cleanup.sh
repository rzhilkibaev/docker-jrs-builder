#!/usr/bin/env bash
# creates repo
#
# this script requires following arguments:
# 1. CTX_FILE - a shell script which is going to be used to pass data between other scripts in the group.

CTX_FILE="$1"

echo "Context file: $CTX_FILE"
source $CTX_FILE

echo "Deleting build data container: $BUILD_DATA_CONTAINER"
docker rm -v $BUILD_DATA_CONTAINER
