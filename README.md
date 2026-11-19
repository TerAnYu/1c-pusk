# 1C-ПУСК Docker Build

Автоматизированная сборка Docker-образа для приложения **1C-ПУСК** (ite-pusk) — инструмента мониторинга инфраструктуры 1С на базе Java/Spring Boot.

## Что это

Проект автоматизирует:
- Распаковку дистрибутива 1C-ПУСК из tarball
- Добавление библиотек 1С Java API из отдельного архива
- Сборку Docker-образа с приложением
- Тегирование версией и `latest`
- Отправку в Docker Registry (опционально)
- Тестирование перед публикацией

## Структура проекта

```
.
├── build.sh              # Основной скрипт сборки
├── test.sh               # Тесты (структура, сборка, запуск)
├── .env                  # Конфигурация реестра (не в git)
├── .env.example          # Шаблон конфигурации
├── .gitignore
├── ite-pusk-*.tar.gz     # Дистрибутив 1C-ПУСК
├── java-api-8.3.11.zip   # Библиотеки 1С Java API
├── build/
│   ├── dockerfile        # Dockerfile образа
│   ├── docker-build.sh   # Скрипт docker build + push
│   ├── entrypoint.sh     # Точка входа контейнера
│   ├── .arg              # Переменные сборки (версия, OS)
│   └── install/
│       └── pusk.tgz      # Упакованное приложение (генерируется)
├── compose/
│   ├── docker-compose.yml
│   ├── data/             # Данные приложения
│   └── log/              # Логи
└── pusk/                 # Распакованное приложение (генерируется)
```

## Быстрый старт

### 1. Подготовка

Скопируйте шаблон конфигурации и заполните:

```bash
cp .env.example .env
nano .env
```

```bash
REGISTRY=your-registry.example.com/
REGISTRY_LOGIN=username
REGISTRY_PASSWORD=password
```

### 2. Сборка образа

```bash
./build.sh              # Собрать образ из последнего ite-pusk-*.tar.gz
./build.sh 1.3.1        # Собрать конкретную версию
./build.sh push         # Собрать, протестировать и отправить в реестр
./build.sh 1.3.1 push   # Конкретная версия + push
```

### 3. Запуск

```bash
cd compose
docker-compose pull   # Скачать образ из GHCR
docker-compose up -d
```

Приложение будет доступно на `http://localhost:8080`.

**Или используйте предсобраный образ напрямую:**
```bash
docker pull ghcr.io/teranyu/1c-pusk:latest
docker run -d -p 8080:8080 --name 1cpusk ghcr.io/teranyu/1c-pusk:latest
```

## Тестирование

```bash
./test.sh               # Все тесты (структура, сборка, запуск)
./test.sh quick         # Только структура и конфигурация (без Docker)
./test.sh build         # + сборка образа
./test.sh run           # + запуск контейнера и healthcheck
```

Тесты проверяют:
- Наличие и валидность tarball
- Структуру распакованного приложения
- Наличие библиотек 1С
- Корректность конфигурации
- Сборку Docker-образа
- Запуск контейнера и прохождение healthcheck

**Важно:** При `./build.sh push` тесты запускаются автоматически. Если тесты не пройдены — push отменяется.

## Как это работает

### Процесс сборки

1. **Поиск tarball** — находится последний `ite-pusk-*.tar.gz` или указанный явно
2. **Извлечение версии** — версия берётся из имени файла (например, `1.3.1`)
3. **Распаковка** — содержимое tarball распаковывается в `pusk/`
4. **Библиотеки 1С** — из `java-api-8.3.11.zip` распаковываются JAR-библиотеки в `pusk/lib/`
   - Архив представляет собой "матрёшку" из 3 вложенных zip
5. **Упаковка** — содержимое `pusk/` упаковывается в `build/install/pusk.tgz`
6. **Обновление конфигурации** — версия обновляется в `.arg` и `docker-compose.yml`
7. **Docker build** — собирается образ с тегами версии и `latest`
8. **Push** (опционально) — автоматический login и отправка обоих тегов в реестр

### Entrypoint

В отличие от оригинального `ite-pusk-linux.sh` (который запускает Java в background для systemd), Docker entrypoint запускает Java напрямую в foreground через `exec`. Это необходимо для корректной работы контейнера.

## Требования

- Docker или Podman
- Bash 4+
- unzip (для распаковки библиотек 1С)
- curl (для healthcheck)

## Необходимые файлы

Перед сборкой необходимо скачать и поместить в корень проекта:

1. **Дистрибутив 1C-ПУСК** — `ite-pusk-*.tar.gz`
   - Скачать с [it-expertise.ru/pusk](https://it-expertise.ru/pusk/#download)
   - Прямая ссылка: `https://it-expertise.ru/pusk/ite-pusk-1.3.1.tar.gz`

2. **Библиотеки 1С Java API** — `java-api-8.3.11.zip` или новее
   - Скачать с [ITS 1C](https://its.1c.ru/db/files/1CITS/EXE/java-api-8.3.11/java-api-8.3.11.zip)
   - Архив содержит вложенные zip-файлы (матрёшка), скрипт распаковывает их автоматически

## Автоматическая сборка (GitHub Actions)

Проект настроен на автоматическую сборку Docker-образа при создании тега `v*`.

### Как использовать

1. Создайте тег и push:
   ```bash
   git tag v1.3.1
   git push origin v1.3.1
   ```

2. GitHub Actions автоматически:
   - Скачает дистрибутив с it-expertise.ru
   - Скачает библиотеки 1С Java API
   - Соберёт Docker-образ
   - Опубликует в GitHub Packages

### Образы

После сборки образы доступны в GitHub Packages:
```bash
docker pull ghcr.io/teranyu/1c-pusk:1.3.1
docker pull ghcr.io/teranyu/1c-pusk:latest
```

### Ручной запуск

Также можно запустить сборку вручную через GitHub UI:
- Перейдите в **Actions** → **Build and Publish Docker Image**
- Нажмите **Run workflow**
- Укажите версию (например, `1.3.1`)

## Файлы конфигурации

### `.env`

```bash
REGISTRY=your-registry.example.com/   # Адрес Docker Registry
REGISTRY_LOGIN=username                # Логин для push
REGISTRY_PASSWORD=password             # Пароль для push
```

### `build/.arg`

```bash
OS_TAG=debian:bookworm-slim            # Базовый образ
REGISTRY=your-registry.example.com/    # Реестр (fallback если нет в .env)
OC_PUSK_VERSION=1.3.1-19.11.2026       # Версия (обновляется автоматически)
OC_PUSK_TYPE=pusk                      # Тип приложения
```

## Обновление версии

1. Положите новый `ite-pusk-X.Y.Z.tar.gz` в корень проекта
2. Запустите `./build.sh push`
3. Скрипт автоматически:
   - Извлечёт версию из имени файла
   - Добавит текущую дату к тегу
   - Обновит `.arg` и `docker-compose.yml`
   - Соберёт и отправит образ

## Healthcheck

Контейнер настраивает healthcheck на `http://localhost:8080/actuator/health` (Spring Boot Actuator). Интервал проверки — 30 секунд.

## Лицензия

Проект предназначен для внутреннего использования.
