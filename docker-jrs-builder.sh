#!/usr/bin/env bash
#
# This script builds docker images of JasperReports Server and it's databases.
#
# Usage: docker-jrs-builder BUILD_ID COMMAND [args...]  (Generic form)
#
#     BUILD_ID     Build id, can be Jenkins $BUILD_ID or something similar used to tell one build from the other
#     COMMAND      One of the following commands with arguments:
#        init BRANCH_CE BRANCH_PRO             (Create a build data container and run jst init BRANCH_CE BRANCH_PRO)
#        build                                 (Run jst build)
#        create-postgres-image IMAGE_NAME      (Create postgres database image with all data in it)
#        clean                                 (Delete temporary files and containers)
#
# When this script runs it looks for configuration.sh file in the current directory.
# This file must define the following variables:
# SVNSERVER_IP    IP address of svnserver.jaspersoft.com
# MVNREPO_IP      IP address of mvnrepo.jaspersoft.com
# When executing commands this script creates build-state-${BUILD_ID}.sh in the current directory
# with variable definitions for all intermediate docker containers. This build state file is used to pass
# temporary container names and other information between different executions of this script for the same build (same BUILD_ID).
#
# To run postgres image: docker run -d -p 5432:5432 -e PGDATA=/var/lib/postgresql/jrs-data <image_name> postgres
# END_DOC

set -e
set -o pipefail

BUILD_ID=$1
COMMAND=$2

BUILD_STATE_FILE=build-state-${BUILD_ID}.sh
CONFIG_FILE=configuration.sh
JST_IMAGE_NAME=rzhilkibaev/jst
POSTGRES_IMAGE_NAME=postgres:9.4

# Loads configuration by sourcing configuration.sh
load_configuration() {
    if [ ! -f "$CONFIG_FILE" ]; then
        log "Configuration file $CONFIG_FILE is not found, exiting"
        exit 1
    fi
    log "Loading configuration from $CONFIG_FILE"
    source "$CONFIG_FILE"
}

# Loads build state by sourcing build-state-$BUILD_ID.sh
load_build_state() {
    if [ ! -f "$BUILD_STATE_FILE" ]; then
        log "No build state file $BUILD_STATE_FILE"
        exit 1
    fi
    log "Loading build state from $BUILD_STATE_FILE"
    source "$BUILD_STATE_FILE"
}

# Creates a data container for build data (sources, jars, class files, etc...)
create_build_data_container() {
    log "Creating build data container..."
    # we don't do jst init here because the output of it is not visible (because of $(...))
    BUILD_DATA_CONTAINER=$(docker run -v /opt/jrs -v /root/.m2 -d $JST_IMAGE_NAME --help)
    log "Created build data container: $BUILD_DATA_CONTAINER"
    echo "BUILD_DATA_CONTAINER=$BUILD_DATA_CONTAINER" > $BUILD_STATE_FILE
}

# Runs jst init from inside a new temporary container, saves all files in the build data container.
jst_init() {
    CE_BRANCH=$1
    PRO_BRANCH=$2
    log "Running jst init $CE_BRANCH $PRO_BRANCH"
    run_docker $JST_IMAGE_NAME init $CE_BRANCH $PRO_BRANCH
}

# Runs jst build from inside a new temporary container, saves build artifacts in the build data container.
jst_build() {
    log "Running jst build..."
    run_docker $JST_IMAGE_NAME build
}

# Starts up postgres
start_postgres() {
    log "Starting up postgres..."
    PG_DATA_CONTAINER=$(docker run --volumes-from $BUILD_DATA_CONTAINER -d $POSTGRES_IMAGE_NAME)
    log "Created postgres data container: $PG_DATA_CONTAINER"
    echo "PG_DATA_CONTAINER=$PG_DATA_CONTAINER" >> $BUILD_STATE_FILE
    log "Waiting for postgres to start up"
    sleep 30s
}

# Creates JRS repo and sampe databases
jst_init_db() {
    log "Running jst init-db..."
    run_docker --link $PG_DATA_CONTAINER:db $JST_IMAGE_NAME init-db
    log "Initialized db"
}

stop_postgres() {
    log "Stopping postgres data container..."
    docker stop $PG_DATA_CONTAINER
}

create_postgres_image() {
    POSTGRES_REPO_IMAGE_NAME="$1"
    start_postgres
    jst_init_db
    stop_postgres
    log "Copying jrs repo data from volume into container"
    PG_REPO_DATA_CONTAINER=$(docker run --volumes-from $PG_DATA_CONTAINER -d $POSTGRES_IMAGE_NAME /bin/bash -c "/bin/cp -r /var/lib/postgresql/data /var/lib/postgresql/jrs-data && chown postgres:postgres -R /var/lib/postgresql/jrs-data")
    echo "PG_REPO_DATA_CONTAINER=$PG_REPO_DATA_CONTAINER" >> $BUILD_STATE_FILE
    log "Created container for jrs repo (postgres): $PG_REPO_DATA_CONTAINER"
    # wait for copy process to finish
    docker attach $PG_REPO_DATA_CONTAINER

    log "Commiting container for jrs repo (postgres) into image: $POSTGRES_REPO_IMAGE_NAME"
    docker commit $PG_REPO_DATA_CONTAINER $POSTGRES_REPO_IMAGE_NAME

    log "Deleting container for jrs repo (postgres): $PG_REPO_DATA_CONTAINER"
    docker rm -v $PG_REPO_DATA_CONTAINER

    log "Deleting db container (postgres): $PG_DATA_CONTAINER"
    docker rm -v $PG_DATA_CONTAINER
}

clean() {
    log "Deleting build data container: $BUILD_DATA_CONTAINER"
    docker rm -v $BUILD_DATA_CONTAINER
    rm "$BUILD_STATE_FILE"
}

run_docker() {
    docker run --rm \
        --volumes-from $BUILD_DATA_CONTAINER \
        --add-host=svnserver.jaspersoft.com:${SVNSERVER_IP} \
        --add-host=mvnrepo.jaspersoft.com:${MVNREPO_IP} \
        "$@"
}

print_usage() {
    sed -e '/END_DOC/,$d' $(basename $0)| tail --lines=+3
}

log() {
    echo "[$(basename $0)] $@"
}

log "$(basename $0) started with following arguments: $@"

load_configuration

case "$COMMAND" in
    init)
        create_build_data_container
        jst_init $3 $4
        ;;
    build)
        load_build_state
        jst_build
        ;;
    create-postgres-image)
        load_build_state
        create_postgres_image $3
        ;;
    clean)
        load_build_state
        clean
        ;;
    *)
        print_usage
        exit 1
esac

