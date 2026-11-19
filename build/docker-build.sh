#!/bin/bash

#rm -f "./install/pusk.tgz"
#tar -zcvf "./install/pusk.tgz" -C "../pusk/" .

set -Eeoa pipefail

script_dir=$(dirname "$(readlink -f "$0")")

CONTEXT_ARG=$(realpath "${script_dir}")

source "${CONTEXT_ARG}/.arg"

# Используем REGISTRY из окружения если задано, иначе из .arg
REGISTRY="${REGISTRY:-${REGISTRY}}"

docker build \
    --build-arg "OS_TAG=${OS_TAG}" \
    --build-arg "OC_PUSK_TYPE=${OC_PUSK_TYPE}" \
    --build-arg "OC_PUSK_VERSION=${OC_PUSK_VERSION}" \
    --build-context install=./install \
    -t "${REGISTRY}${OC_PUSK_TAG}" \
    .

echo ">> Тегирование образа как latest"
docker tag "${REGISTRY}${OC_PUSK_TAG}" "${REGISTRY}${OC_PUSK_TAGL}"

if [ "${1}" = "push" ] && [ -n "${REGISTRY}" ]; then

    # Автоматический login если заданы учётные данные
    if [ -n "${REGISTRY_LOGIN}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
        echo ">> Docker login в ${REGISTRY} (автоматически)"
        echo "${REGISTRY_PASSWORD}" | docker login "${REGISTRY}" --username "${REGISTRY_LOGIN}" --password-stdin
    else
        echo ">> Docker login для отправки образа в реестр ${REGISTRY}"
        docker login ${REGISTRY}
    fi

    echo ">> Отправка образа ${REGISTRY}${OC_PUSK_TAG}"
    docker push "${REGISTRY}${OC_PUSK_TAG}"
    echo ">> Отправка тега ${REGISTRY}${OC_PUSK_TAGL}"
    docker push "${REGISTRY}${OC_PUSK_TAGL}"

    echo ">> Docker logout из ${REGISTRY}"
    docker logout ${REGISTRY}

fi
