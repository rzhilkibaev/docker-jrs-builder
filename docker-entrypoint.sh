#!/bin/bash
set -e

configure_buildomatic() {
# configure buildomatic
cat >/opt/jrs/ce/buildomatic/default_master.properties <<EOL
appServerType = skipAppServerCheck
dbType=postgresql
dbHost=localhost
dbUsername=postgres
dbPassword=postgres
maven = $M2_HOME/bin/mvn
mvn-mirror=http://mvnrepo.jaspersoft.com:8081/artifactory/repo
js-path = /opt/jrs/ce
js-pro-path = /opt/jrs/pro
EOL
}

if [ "$1" = 'help' ]; then
    echo "Usage:"
    echo "    docker run -it [OPTIONS] image shell"
    echo "    docker run [OPTIONS] image URL_CE URL_PRO"

elif [ "$1" = 'shell' ]; then
    exec /bin/bash

else
    URL_CE="$1"
    URL_PRO="$2"
    echo "URL_CE: $URL_CE"
    echo "URL_PRO: $URL_PRO"
    svn checkout $URL_CE /opt/jrs/ce
    svn checkout $URL_PRO /opt/jrs/pro
    cd /opt/jrs/ce/buildomatic
    configure_buildomatic
    ant build-src-all
fi
