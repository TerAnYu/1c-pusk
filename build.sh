#!/bin/bash
#
# Автоматическая сборка Docker-образа 1c-pusk
#
# Использование:
#   ./build.sh              — собрать образ из последнего ite-pusk-*.tar.gz
#   ./build.sh push         — собрать и отправить в реестр
#   ./build.sh 1.3.1        — собрать конкретную версию
#   ./build.sh 1.3.1 push   — конкретную версию и отправить

set -Eeo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${script_dir}/build"
arg_file="${build_dir}/.arg"
compose_file="${script_dir}/compose/docker-compose.yml"

# --- Загрузка .env ---
if [ -f "${script_dir}/.env" ]; then
    set -a
    source "${script_dir}/.env"
    set +a
fi

# --- Парсинг аргументов ---
PUSH=false
VERSION_OVERRIDE=""

for arg in "$@"; do
    case "$arg" in
        push) PUSH=true ;;
        *)    VERSION_OVERRIDE="$arg" ;;
    esac
done

# --- Поиск tarball ---
if [ -n "$VERSION_OVERRIDE" ]; then
    TARBALL="${script_dir}/ite-pusk-${VERSION_OVERRIDE}.tar.gz"
    if [ ! -f "$TARBALL" ]; then
        echo "Ошибка: файл ${TARBALL} не найден"
        exit 1
    fi
else
    TARBALL="$(ls -t "${script_dir}"/ite-pusk-*.tar.gz 2>/dev/null | head -1)"
    if [ -z "$TARBALL" ] || [ ! -f "$TARBALL" ]; then
        echo "Ошибка: не найден файл ite-pusk-*.tar.gz в ${script_dir}"
        exit 1
    fi
fi

# --- Извлечение версии ---
TARBALL_NAME="$(basename "$TARBALL")"
VERSION="$(echo "$TARBALL_NAME" | sed 's/^ite-pusk-//; s/\.tar\.gz$//')"
DATE_TAG="$(date +%d.%m.%Y)"
FULL_VERSION="${VERSION}-${DATE_TAG}"

echo "=== Сборка 1c-pusk ==="
echo "Файл:    ${TARBALL_NAME}"
echo "Версия:  ${FULL_VERSION}"
echo "Push:    ${PUSH}"
echo ""

# --- Распаковка в pusk/ ---
echo ">> Распаковка в pusk/ ..."
rm -rf "${script_dir}/pusk"
mkdir -p "${script_dir}/pusk"
# Тарболл содержит корневой каталог pusk/, убираем его
tar -zxf "$TARBALL" --strip-components=1 -C "${script_dir}/pusk"

# --- Распаковка библиотек 1С из java-api ---
JAVA_API_ZIP="${script_dir}/java-api-8.3.11.zip"
if [ -f "$JAVA_API_ZIP" ]; then
    echo ">> Распаковка библиотек 1С из java-api-8.3.11.zip ..."
    TEMP_DIR=$(mktemp -d)
    # Матрёшка: java-api-8.3.11.zip → java-api-1.6.7.zip → com._1c.v8.ibis.admin-1.6.7.zip → lib/*.jar
    unzip -q "$JAVA_API_ZIP" -d "$TEMP_DIR"
    unzip -q "$TEMP_DIR"/java-api-8.3.11/java-api-1.6.7.zip -d "$TEMP_DIR"
    unzip -q "$TEMP_DIR"/java-api-1.6.7/com._1c.v8.ibis.admin-1.6.7.zip -d "$TEMP_DIR"
    # Копируем библиотеки в pusk/lib/
    mkdir -p "${script_dir}/pusk/lib"
    cp "$TEMP_DIR"/com._1c.v8.ibis.admin-1.6.7/lib/*.jar "${script_dir}/pusk/lib/"
    rm -rf "$TEMP_DIR"
    echo "   Скопировано $(ls "${script_dir}/pusk/lib/"*.jar 2>/dev/null | wc -l) библиотек"
else
    echo "⚠ java-api-8.3.11.zip не найден — библиотеки 1С не будут добавлены"
fi

# --- Упаковка pusk.tgz ---
echo ">> Создание install/pusk.tgz ..."
mkdir -p "${build_dir}/install"
rm -f "${build_dir}/install/pusk.tgz"
tar -zcf "${build_dir}/install/pusk.tgz" -C "${script_dir}/pusk" .

# --- Обновление .arg ---
echo ">> Обновление .arg (версия ${FULL_VERSION}) ..."
sed -i "s/^OC_PUSK_VERSION=.*/OC_PUSK_VERSION=\"${FULL_VERSION}\"/" "$arg_file"

# --- Обновление docker-compose.yml ---
IMAGE_TAG="${VERSION}-${DATE_TAG}"
REGISTRY="${REGISTRY:-}"
echo ">> Обновление docker-compose.yml (тег ${IMAGE_TAG}) ..."
if [ -w "$compose_file" ]; then
    sed -i "s|image: .*1c/pusk:.*|image: ${REGISTRY}1c/pusk:${IMAGE_TAG}|" "$compose_file"
else
    echo ">> Требуется sudo для обновления docker-compose.yml (файл принадлежит root)"
    sudo sed -i "s|image: .*1c/pusk:.*|image: ${REGISTRY}1c/pusk:${IMAGE_TAG}|" "$compose_file"
fi

# --- Тесты ---
if [ "$PUSH" = true ]; then
    echo ">> Запуск тестов перед push ..."
    if [ -f "${script_dir}/test.sh" ]; then
        if ! bash "${script_dir}/test.sh" quick; then
            echo "Ошибка: тесты не пройдены. Push отменён."
            exit 1
        fi
    else
        echo "⚠ test.sh не найден — пропускаем тесты"
    fi
    echo ""
fi

# --- Сборка образа ---
echo ">> Docker build ..."
cd "$build_dir"

# Экспортируем переменные для docker-build.sh
export REGISTRY REGISTRY_LOGIN REGISTRY_PASSWORD

bash ./docker-build.sh ${PUSH:+push}

echo ""
echo "=== Готово ==="
echo "Образ: ${REGISTRY}1c/pusk:${IMAGE_TAG}"
echo "Тег:   ${REGISTRY}1c/pusk:latest"
