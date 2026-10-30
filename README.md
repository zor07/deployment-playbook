# Deployment Playbook

Пошаговое руководство по настройке CI/CD и развёртыванию Java-приложений на VPS.

## Содержание

1. [Локальная контейнеризация приложения](docs/01-local-docker.md)
2. [Подготовка VPS](docs/02-vps-setup.md)
3. [Создание инфраструктурного репозитория](docs/03-infra-repository.md)
4. [Первоначальное развёртывание на VPS](docs/04-first-deploy.md)
5. [Настройка GitHub Actions CI](docs/05-github-actions-ci.md)
6. [Настройка GitHub Actions CD](docs/06-github-actions-cd.md)
7. [Настройка nginx и HTTPS](docs/07-nginx-https.md)
8. [Проверка CI/CD и развёртывания](docs/08-verification.md)

## Технологический стек

- Java 21, Spring Boot, Maven
- Docker, Docker Compose
- PostgreSQL
- GitHub Actions
- GitHub Container Registry (GHCR)
- Ubuntu Server
- nginx
- Let's Encrypt (Certbot)

## Архитектура CI/CD
```text
Developer
    |
    | git push origin master
    v
GitHub Repository
    |
    v
GitHub Actions
    |
    | 1. Build Docker image
    | 2. Push image :latest
    v
GitHub Container Registry (GHCR)
    |
    |                         GitHub Actions
    |                               |
    |                               | SSH
    |                               v
    |                             VPS
    |                               |
    |                         deploy.sh
    |                               |
    +------ docker compose pull ----+
                                    |
                            docker compose up -d
                                    |
                         +----------+----------+
                         |                     |
                    Spring Boot           PostgreSQL
                         |
                        nginx
                         |
                       HTTPS
                         |
                       Client
```

### Принцип работы

1. Разработчик отправляет изменения в ветку `master`.
2. GitHub Actions собирает Docker-образ приложения.
3. Образ публикуется в GHCR с тегом `latest`.
4. GitHub Actions подключается к VPS по SSH и запускает `deploy.sh`.
5. Скрипт скачивает актуальные образы и обновляет контейнеры через Docker Compose.
6. nginx принимает внешние HTTP/HTTPS-запросы и проксирует их в приложение.

На VPS размещаются инфраструктурные конфигурации и Docker-образы. Исходный код приложения на сервер не копируется.

## Структура репозиториев

Для каждого приложения используются два независимых репозитория.

**Application repository**

Содержит исходный код, `Dockerfile` и workflow GitHub Actions.

**Infrastructure repository**

Содержит `docker-compose.yml`, `deploy.sh` и шаблон переменных окружения `.env.example`.

На VPS клонируется только infrastructure repository.

## Примеры конфигураций

Каталог `examples/` содержит файлы Dockerfile, Docker Compose, GitHub Actions, nginx, Logback и скрипт деплоя, используемые в инструкциях.
