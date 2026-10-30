# Deployment Playbook

Пошаговое руководство по настройке CI/CD и развёртыванию Java-приложений на VPS.

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
```yaml
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

## Порядок развёртывания

| Этап                         | Документация      |
| ---------------------------- | ----------------- |
| 1. Локальная контейнеризация | Local Docker      |
| 2. Подготовка VPS            | VPS Setup         |
| 3. Подготовка инфраструктуры | Infra Repository  |
| 4. Первоначальный деплой     | First Deploy      |
| 5. Настройка CI              | GitHub Actions CI |
| 6. Настройка CD              | GitHub Actions CD |
| 7. Настройка HTTPS           | nginx & HTTPS     |
| 8. Проверка развёртывания    | Verification      |

## Примеры конфигураций

Каталог `examples/` содержит файлы Dockerfile, Docker Compose, GitHub Actions, nginx, Logback и скрипт деплоя, используемые в инструкциях.
