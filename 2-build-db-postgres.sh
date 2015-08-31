#!/usr/bin/env bash
# creates repo
#
# this script requires following arguments:
# 1. CTX_FILE - a shell script which is going to be used to pass data between other scripts in the group.

set -e
set -o pipefail

CTX_FILE="$1"

POSTGRES_IMAGE_NAME=postgres:9.4
POSTGRES_REPO_IMAGE_NAME=repo-pg-test

echo "Context file: $CTX_FILE"
source $CTX_FILE
echo "Using build data container: $BUILD_DATA_CONTAINER"

# start up postgres
echo "Starting up database (postgres)..."
PG_DATA_CONTAINER=$(docker run --volumes-from $BUILD_DATA_CONTAINER -d $POSTGRES_IMAGE_NAME)
echo "Created postgres data container: $PG_DATA_CONTAINER"
echo "PG_DATA_CONTAINER=$PG_DATA_CONTAINER" >> $CTX_FILE
echo "Waiting for postgres to start up"
sleep 30s

# create repo (postgres)
echo "Creating jrs repo (postgres)..."
docker run --rm --volumes-from $BUILD_DATA_CONTAINER --link $PG_DATA_CONTAINER:db $JST_IMAGE_NAME init-db
echo "Created jrs repo (postgres)"

echo "Stopping postgres data container..."
docker stop $PG_DATA_CONTAINER

echo "Copying jrs repo data from volume into container"
PG_FINAL_CONTAINER=$(docker run --volumes-from $PG_DATA_CONTAINER -d $POSTGRES_IMAGE_NAME /bin/bash -c "/bin/cp -r /var/lib/postgresql/data /var/lib/postgresql/jrs-data && chown postgres:postgres -R /var/lib/postgresql/jrs-data")
echo "Created container for jrs repo (postgres): $PG_FINAL_CONTAINER"
docker attach $PG_FINAL_CONTAINER

echo "Commiting container for jrs repo (postgres) into image: $POSTGRES_REPO_IMAGE_NAME"
docker commit $PG_FINAL_CONTAINER $POSTGRES_REPO_IMAGE_NAME

echo "Deleting container for jrs repo (postgres): $PG_FINAL_CONTAINER"
docker rm -v $PG_FINAL_CONTAINER

echo "Deleting db container (postgres): $PG_DATA_CONTAINER"
docker rm -v $PG_DATA_CONTAINER
