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
# When this script runs it looks for /etc/docker-jrs-builder/configuration.sh file.
# This file must define the following variables:
# SVNSERVER_IP    IP address of svnserver.jaspersoft.com
# MVNREPO_IP      IP address of mvnrepo.jaspersoft.com
# When executing commands this script creates /var/tmp/build-state-${BUILD_ID}.sh in the current directory
# with variable definitions for all intermediate docker containers. This build state file is used to pass
# temporary container names and other information between different executions of this script for the same build (same BUILD_ID).
#
# To run PostgreSQL image: docker run -d -p 5432:5432 <image_name>
# port 5432, username=postgres, password=postgres 
#
# To run Oracle image: docker run -d -p 1521:1521 <image_name>
# port 1521, sid=xe, username=system, password=oracle, username=jasperserver, password=password
#
# To run MySQL image: docker run -d -p 3306:3306 <image_name>
# port 3306, username=root, password=password
# END_DOC

set -e
set -o pipefail

BUILD_ID=$1
COMMAND=$2

BUILD_STATE_FILE=/var/tmp/build-state-${BUILD_ID}.sh
CONFIG_FILE=/etc/docker-jrs-builder/configuration.sh
JST_IMAGE_NAME=rzhilkibaev/jst
PG_BASE_IMAGE_NAME=postgres:9.4
ORA_BASE_IMAGE_NAME=wnameless/oracle-xe-11g
MYSQL_BASE_IMAGE_NAME=rzhilkibaev/jrs-mysql

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
    BUILD_DATA_CONTAINER=$(docker run -v /opt/jrs -v /home/jst -d --name build-data-$BUILD_ID $JST_IMAGE_NAME --help)
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
start_postgresql() {
    log "Starting up Postgres..."
    DB_DATA_CONTAINER=$(docker run --volumes-from $BUILD_DATA_CONTAINER -d -e PGDATA=/var/lib/postgres/jrs-data $PG_BASE_IMAGE_NAME)
    log "Created Postgres data container: $DB_DATA_CONTAINER"
    log "Waiting for Postgres to start up"
    sleep 30s
}

start_oracle() {
    log "Starting up Oracle..."
    DB_DATA_CONTAINER=$(docker run --volumes-from $BUILD_DATA_CONTAINER -d $ORA_BASE_IMAGE_NAME)
    log "Created Oracle data container: $DB_DATA_CONTAINER"
    log "Waiting for Oracle to start up"
    sleep 30s
}

# Configures buildomatic
jst_configure() {
    log "Running jst configure for db type $DB_TYPE"
    run_docker $JST_IMAGE_NAME configure --dbType=$DB_TYPE --dbHost=db --appServerType=skipAppServerCheck
}

# Creates JRS repo and sample databases
jst_init_db() {
    log "Running jst init-db..."
    run_docker --link $DB_DATA_CONTAINER:db $JST_IMAGE_NAME init-db
    log "Initialized db"
}

stop_db() {
    log "Stopping db data container..."
    docker stop $DB_DATA_CONTAINER
}

create_postgresql_image() {
    jst_configure
    start_postgresql
    jst_init_db
    stop_db

    log "Commiting Postgres container into image: $OUTPUT_IMAGE_NAME"
        #--change='CMD ["postgres"]' \
    docker commit \
        --change="ENV PGDATA /var/lib/postgres/jrs-data" \
        $DB_DATA_CONTAINER $OUTPUT_IMAGE_NAME

    log "Deleting Postgres container: $DB_DATA_CONTAINER"
    docker rm -v $DB_DATA_CONTAINER
}

create_oracle_image() {
    jst_configure
    start_oracle
    jst_init_db
    stop_db

    log "Commiting Oracle container into image: $OUTPUT_IMAGE_NAME"
        #--change='CMD "/usr/sbin/startup.sh && /usr/sbin/sshd -D"' \
    docker commit \
        $DB_DATA_CONTAINER $OUTPUT_IMAGE_NAME

    log "Deleting Oracle container: $DB_DATA_CONTAINER"
    docker rm -v $DB_DATA_CONTAINER
}

create_mysql_image() {
    jst_configure
    start_mysql
    jst_init_db
    stop_db

    log "Commiting MySQL container into image: $OUTPUT_IMAGE_NAME"
        #--change='CMD ["mysqld"]' \
    docker commit \
        $DB_DATA_CONTAINER $OUTPUT_IMAGE_NAME

    log "Deleting MySQL container: $DB_DATA_CONTAINER"
    docker rm -v $DB_DATA_CONTAINER
}

start_mysql() {
    log "Starting up MySQL..."
    DB_DATA_CONTAINER=$(docker run --volumes-from $BUILD_DATA_CONTAINER -d $MYSQL_BASE_IMAGE_NAME)
    log "Created MySQL data container: $DB_DATA_CONTAINER"
    log "Waiting for MySQL to start up"
    sleep 30s
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

log "Started with following arguments: $@"

load_configuration

case "$COMMAND" in
    init)
        create_build_data_container
        jst_init $3 $4
        ;;
    build)
        load_build_state
        # by default buildomatic uses tomcat7
        # we need to reconfigure it before running build
        DB_TYPE=postgresql
        jst_configure
        jst_build
        ;;
    create-db-image)
        DB_TYPE=$3
        OUTPUT_IMAGE_NAME="$4"
        load_build_state
        create_${DB_TYPE}_image
        ;;
    clean)
        load_build_state
        clean
        ;;
    *)
        print_usage
        exit 1
esac

