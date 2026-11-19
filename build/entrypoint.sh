#!/usr/bin/env bash

set -Eeo pipefail

PTH="/var/opt/1C/pusk"

setup_pusk_healthcheck() {

    if [ ! -f "/healthcheck.sh" ]; then
        echo "curl --output /dev/null --silent --fail --head --retry 0 http://localhost:8080/actuator/health || exit 1" > /healthcheck.sh;
        chmod 766 /healthcheck.sh;
    fi;

}

run_pusk() {

    if [ ! -f "${PTH}/data/application.properties.sample" ]; then
        cp "${PTH}/application.properties.sample" "${PTH}/data/application.properties.sample"
    fi

    echo "Begining 1c-pusk"

    JAVA_HOME=$(readlink -f /usr/bin/java | sed "s:/bin/java::")
    export JAVA_HOME

    cd "${PTH}/bin"
    exec "${JAVA_HOME}/bin/java" \
        -cp "ite-pusk.jar:../lib/*" \
        -Dloader.main=com.ite.utils.pusk.Application \
        org.springframework.boot.loader.PropertiesLauncher \
        --spring.config.import=optional:"${PTH}/data/application.properties"

}

setup_pusk_healthcheck

if [ "$1" == "sh" ]; then
    exec sh
elif [ "$1" == "tail" ]; then
    tail -f /dev/null
elif [ "$1" == "bash" ]; then
    exec /bin/bash
else
    run_pusk
fi

exit 0
