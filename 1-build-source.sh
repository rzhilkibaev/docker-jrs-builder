#!/usr/bin/env bash
# builds the whole thing
# this script requires following arguments:
# 1. CTX_FILE - a shell script which is going to be used to pass data between other scripts in the group.
# 2. CE_BRANCH - svn branch name for ce
# 3. PRO_BRANCH - svn branch name fro pro

set -e
set -o pipefail

CTX_FILE="$1"
CE_BRANCH="$2"
PRO_BRANCH="$3"

JST_IMAGE_NAME=rzhilkibaev/jst

echo "Context file: $CTX_FILE"
echo "ce branch: $CE_BRANCH"
echo "pro branch: $PRO_BRANCH"

echo "JST_IMAGE_NAME=$JST_IMAGE_NAME" > $CTX_FILE

# create data container for build data
# we don't do jst init here because the output of it is not visible (because of $(...))
echo "Creating build data container..."
#BUILD_DATA_CONTAINER=5d4e9073e3ac01c25a5e063f04aaec57599f41127bd078cb60a361e4fbb05f41
BUILD_DATA_CONTAINER=$(docker run -v /opt/jrs -v /root/.m2 -d $JST_IMAGE_NAME --help)
sleep 5s
echo "Created build data container: $BUILD_DATA_CONTAINER"
echo "BUILD_DATA_CONTAINER=$BUILD_DATA_CONTAINER" >> $CTX_FILE

# jst init
echo "Running jst init..."
docker run --rm --volumes-from $BUILD_DATA_CONTAINER $JST_IMAGE_NAME init anonymous $CE_BRANCH $PRO_BRANCH

# jst build
echo "Running jst build..."
docker run --rm --volumes-from $BUILD_DATA_CONTAINER $JST_IMAGE_NAME build
