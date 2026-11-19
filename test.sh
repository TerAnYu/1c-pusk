#!/bin/bash
#
# Тесты для проверки работоспособности сборки 1c-pusk
#
# Использование:
#   ./test.sh          — все тесты
#   ./test.sh quick    — только быстрые (без docker run)
#   ./test.sh build    — только тесты сборки
#   ./test.sh run      — только запуск контейнера + healthcheck

set -Eo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${script_dir}/build"
compose_dir="${script_dir}/compose"

PASS=0
FAIL=0
SKIP=0

pass() { ((PASS++)); echo "  ✓ $1"; }
fail() { ((FAIL++)); echo "  ✗ $1"; }
skip() { ((SKIP++)); echo "  ⊘ $1 (пропущен)"; }

section() { echo ""; echo "── $1 ──"; }

# =============================================
# 1. Проверка tarball
# =============================================
test_tarball() {
    section "Тарболл"

    local tarball
    tarball="$(ls -t "${script_dir}"/ite-pusk-*.tar.gz 2>/dev/null | head -1)"

    if [ -z "$tarball" ]; then
        fail "ite-pusk-*.tar.gz не найден в корне проекта"
        return 1
    fi
    pass "Найден: $(basename "$tarball")"

    # Проверка что это валидный gzip
    if gzip -t "$tarball" 2>/dev/null; then
        pass "Валидный gzip-архив"
    else
        fail "Файл не является валидным gzip"
        return 1
    fi

    # Проверка размера (не пустой)
    local size
    size=$(stat -c%s "$tarball")
    if [ "$size" -gt 1000 ]; then
        pass "Размер: ${size} байт"
    else
        fail "Архив слишком мал (${size} байт) — вероятно пуст"
        return 1
    fi
}

# =============================================
# 2. Проверка структуры pusk/
# =============================================
test_pusk_structure() {
    section "Структура pusk/"

    if [ ! -d "${script_dir}/pusk" ]; then
        fail "Каталог pusk/ не существует (запустите build.sh)"
        return 1
    fi
    pass "Каталог pusk/ существует"

    local required_files=(
        "ite-pusk-linux.sh"
        "data/application.properties.sample"
        "bin/ite-pusk.jar"
    )

    for f in "${required_files[@]}"; do
        if [ -f "${script_dir}/pusk/$f" ]; then
            pass "pusk/$f"
        else
            fail "pusk/$f — отсутствует"
        fi
    done

    # Проверка библиотек 1С (опционально, могут отсутствовать в новых версиях)
    local lib_count
    lib_count=$(find "${script_dir}/pusk/lib" -name "*.jar" 2>/dev/null | wc -l)
    if [ "$lib_count" -gt 0 ]; then
        pass "Библиотеки 1С: найдено ${lib_count} jar"
    else
        echo "  ⚠ pusk/lib/ пуст — библиотеки 1С отсутствуют (может быть нормально для новых версий)"
    fi

    # Проверка что ite-pusk-linux.sh исполняемый
    if [ -x "${script_dir}/pusk/ite-pusk-linux.sh" ]; then
        pass "ite-pusk-linux.sh — исполняемый"
    else
        fail "ite-pusk-linux.sh — не исполняемый (chmod +x)"
    fi
}

# =============================================
# 3. Проверка install/pusk.tgz
# =============================================
test_install_tgz() {
    section "install/pusk.tgz"

    local tgz="${build_dir}/install/pusk.tgz"

    if [ ! -f "$tgz" ]; then
        fail "build/install/pusk.tgz не создан (запустите build.sh)"
        return 1
    fi
    pass "build/install/pusk.tgz существует"

    if gzip -t "$tgz" 2>/dev/null; then
        pass "Валидный gzip-архив"
    else
        fail "Не валидный gzip"
        return 1
    fi

    # Проверка что внутри есть ключевые файлы
    local contents
    contents=$(tar -tzf "$tgz" 2>/dev/null)

    if echo "$contents" | grep -q "ite-pusk-linux.sh"; then
        pass "Содержит ite-pusk-linux.sh"
    else
        fail "Не содержит ite-pusk-linux.sh"
    fi

    if echo "$contents" | grep -q "bin/ite-pusk.jar"; then
        pass "Содержит bin/ite-pusk.jar"
    else
        fail "Не содержит bin/ite-pusk.jar"
    fi
}

# =============================================
# 4. Проверка конфигурации
# =============================================
test_config() {
    section "Конфигурация"

    # .arg
    local arg_file="${build_dir}/.arg"
    if [ -f "$arg_file" ]; then
        pass ".arg существует"

        if grep -q 'OC_PUSK_VERSION=' "$arg_file"; then
            local ver
            ver=$(grep '^OC_PUSK_VERSION=' "$arg_file" | cut -d'"' -f2)
            pass "Версия: ${ver}"
        else
            fail "OC_PUSK_VERSION не задан в .arg"
        fi

        if grep -q 'REGISTRY=' "$arg_file"; then
            pass "REGISTRY задан"
        else
            fail "REGISTRY не задан в .arg"
        fi
    else
        fail ".arg не найден"
    fi

    # docker-compose.yml
    local compose="${compose_dir}/docker-compose.yml"
    if [ -f "$compose" ]; then
        pass "docker-compose.yml существует"

        if grep -q 'image:.*1c/pusk:' "$compose"; then
            local img
            img=$(grep 'image:' "$compose" | grep -v '^#' | head -1 | sed 's/.*image: *//')
            pass "Образ: ${img}"
        else
            fail "image не задан в docker-compose.yml"
        fi
    else
        fail "docker-compose.yml не найден"
    fi

    # Dockerfile
    local dockerfile="${build_dir}/dockerfile"
    if [ -f "$dockerfile" ]; then
        pass "Dockerfile существует"

        if grep -q 'ENTRYPOINT' "$dockerfile"; then
            pass "ENTRYPOINT задан"
        else
            fail "ENTRYPOINT не задан"
        fi

        if grep -q 'HEALTHCHECK' "$dockerfile"; then
            pass "HEALTHCHECK задан"
        else
            fail "HEALTHCHECK не задан"
        fi

        if grep -q 'usr1ce' "$dockerfile"; then
            pass "Пользователь usr1ce создаётся"
        else
            fail "Пользователь usr1ce не создаётся в Dockerfile"
        fi
    else
        fail "Dockerfile не найден"
    fi

    # entrypoint.sh
    local entrypoint="${build_dir}/entrypoint.sh"
    if [ -f "$entrypoint" ]; then
        pass "entrypoint.sh существует"

        if grep -q 'exec.*java' "$entrypoint"; then
            pass "Java запускается напрямую через exec (foreground)"
        else
            fail "Java не запускается через exec — проверьте entrypoint.sh"
        fi
    else
        fail "entrypoint.sh не найден"
    fi
}

# =============================================
# 5. Docker build (dry-run)
# =============================================
test_docker_build() {
    section "Docker build"

    if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
        skip "Docker/Podman не установлен"
        return 0
    fi

    echo "  Сборка образа (это займёт время)..."
    cd "$build_dir"
    if bash ./docker-build.sh 2>&1; then
        pass "docker build — успешен"
    else
        fail "docker build — ошибка"
        return 1
    fi

    # Проверка что образ создан
    source "${build_dir}/.arg"
    local tag="${REGISTRY}${OC_PUSK_TAG}"
    if docker image inspect "$tag" &>/dev/null || podman image inspect "$tag" &>/dev/null; then
        pass "Образ ${tag} существует"
    else
        fail "Образ ${tag} не найден"
    fi

    # Проверка latest тега
    local latest="${REGISTRY}${OC_PUSK_TAGL}"
    if docker image inspect "$latest" &>/dev/null || podman image inspect "$latest" &>/dev/null; then
        pass "Тег ${latest} существует"
    else
        fail "Тег ${latest} не найден"
    fi
}

# =============================================
# 6. Docker run + healthcheck
# =============================================
test_docker_run() {
    section "Docker run + healthcheck"

    if ! command -v docker &>/dev/null && ! command -v podman &>/dev/null; then
        skip "Docker/Podman не установлен"
        return 0
    fi

    source "${build_dir}/.arg"
    local tag="${REGISTRY}${OC_PUSK_TAG}"
    local container_name="pusk-test-$$"

    echo "  Запуск контейнера ${container_name}..."

    # Определяем docker/podman
    local runtime="docker"
    command -v docker &>/dev/null || runtime="podman"

    $runtime run -d --name "$container_name" -p 18080:8080 "$tag" 2>/dev/null

    if [ $? -ne 0 ]; then
        fail "Не удалось запустить контейнер"
        $runtime rm -f "$container_name" 2>/dev/null
        return 1
    fi
    pass "Контейнер запущен"

    # Ждём запуска (до 30 секунд)
    echo "  Ожидание запуска приложения..."
    local healthy=false
    for i in $(seq 1 30); do
        if curl --silent --fail --retry 0 http://localhost:18080/actuator/health &>/dev/null; then
            healthy=true
            break
        fi
        sleep 1
    done

    if $healthy; then
        pass "Healthcheck пройден (${i}с)"
    else
        fail "Healthcheck не пройден за 30с"
        echo "  Логи контейнера:"
        $runtime logs "$container_name" 2>&1 | tail -10 | sed 's/^/    /'
    fi

    # Очистка
    $runtime stop "$container_name" &>/dev/null
    $runtime rm -f "$container_name" &>/dev/null
    pass "Контейнер остановлен и удалён"
}

# =============================================
# Main
# =============================================
MODE="${1:-all}"

echo "╔═══════════════════════════════════════╗"
echo "║   Тесты сборки 1c-pusk               ║"
echo "╚═══════════════════════════════════════╝"

case "$MODE" in
    quick)
        test_tarball
        test_pusk_structure
        test_install_tgz
        test_config
        ;;
    build)
        test_tarball
        test_pusk_structure
        test_install_tgz
        test_config
        test_docker_build
        ;;
    run)
        test_docker_run
        ;;
    all|"")
        test_tarball
        test_pusk_structure
        test_install_tgz
        test_config
        test_docker_build
        test_docker_run
        ;;
    *)
        echo "Использование: $0 [all|quick|build|run]"
        exit 1
        ;;
esac

echo ""
echo "═══════════════════════════════════════"
echo "Результат: ✓ ${PASS} пройдено | ✗ ${FAIL} провалено | ⊘ ${SKIP} пропущено"
echo "═══════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
