# Проверка CI/CD и развёртывания

## Назначение

Проверка полного цикла сборки, публикации и автоматического развёртывания Spring Boot приложения на VPS.

На этом этапе все компоненты уже должны быть настроены:

- GitHub Actions.
- GitHub Container Registry (GHCR).
- SSH-доступ GitHub Actions к VPS.
- Инфраструктурный репозиторий.
- Docker Compose.
- Spring Boot и PostgreSQL.
- nginx и HTTPS.
- Логирование приложения.

Цель — убедиться, что изменение исходного кода приводит к обновлению работающего приложения на VPS.

## 1. Архитектура проверяемого процесса

```text
Developer
    |
    | git push
    v
GitHub Repository (master)
    |
    v
GitHub Actions
    |
    ├── Checkout
    ├── Docker build
    ├── Push image:latest → GHCR
    |
    └── SSH → VPS
                 |
                 ├── git pull (infra)
                 └── deploy.sh
                         |
                         ├── docker compose pull
                         ├── docker compose up -d
                         └── docker image prune -f
                                  |
                                  v
                            Spring Boot
                                  |
                              PostgreSQL

Client → HTTPS → nginx → Spring Boot
```

Используется тег Docker-образа `latest`. Отдельные версии образов и механизм автоматического rollback в данной конфигурации не предусмотрены.

## 2. Проверка GitHub Actions

В основном репозитории приложения открыть:

`Actions → Build and Deploy`

Убедиться, что последний workflow завершился успешно.

Проверить выполнение шагов:

1. `Checkout` — исходный код получен.
2. `Log in to GHCR` — авторизация в реестре выполнена.
3. `Build and push Docker image` — образ собран и опубликован.
4. `Deploy on VPS` — SSH-подключение и запуск скрипта завершились успешно.

При ошибке открыть логи соответствующего шага.

Настройки workflow находятся в основном репозитории приложения:

```text
.github/workflows/deploy.yml
```

## 3. Проверка Docker-образа в GHCR

Проверить наличие Docker-образа в GitHub Packages.

Ожидаемое имя:

```text
ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

При необходимости проверить возможность скачивания образа на компьютере с Docker:

```bash
docker pull ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

Для приватного образа предварительно выполнить авторизацию в GHCR.

Успешное скачивание подтверждает доступность опубликованного образа.

## 4. Проверка контейнеров на VPS

Подключиться к серверу:

```bash
ssh root@<VPS_IP>
```

Перейти в инфраструктурный репозиторий:

```bash
cd /opt/<APPLICATION>-infra
```

Проверить контейнеры:

```bash
docker compose ps
```

Ожидается, что сервисы `app` и `db` находятся в состоянии `Up`.

Посмотреть используемый образ приложения:

```bash
docker compose images
```

Посмотреть все работающие контейнеры:

```bash
docker ps
```

## 5. Проверка Spring Boot

Посмотреть последние логи:

```bash
docker compose logs --tail=100 app
```

Посмотреть логи в реальном времени:

```bash
docker compose logs -f app
```

Проверить доступность приложения непосредственно на VPS:

```bash
curl -i http://127.0.0.1:8080
```

Корневой маршрут может возвращать `404` или `401`, если это предусмотрено приложением.

Для проверки бизнес-функциональности использовать существующий HTTP endpoint приложения.

Убедиться, что в логах отсутствуют ошибки, препятствующие запуску приложения.

## 6. Проверка PostgreSQL

Проверить готовность PostgreSQL:

```bash
docker compose exec db pg_isready -U user -d bot_db
```

Если в `.env` используются другие значения `DB_USERNAME` и `DB_NAME`, заменить аргументы команды на соответствующие.

Успешный результат:

```text
accepting connections
```

Проверить состояние контейнера БД:

```bash
docker compose ps db
```

Проверить наличие Docker volume:

```bash
docker volume ls
```

В данной архитектуре PostgreSQL использует named volume `pgdata`, который сохраняется при обычном пересоздании контейнеров.

## 7. Проверка nginx

nginx работает в отдельном Docker-контейнере с `network_mode: host`.

Проверить контейнер:

```bash
docker ps --filter name=nginx
```

Проверить конфигурацию:

```bash
docker exec nginx nginx -t
```

Посмотреть логи:

```bash
docker logs nginx --tail=100
```

Проверить HTTP:

```bash
curl -I http://example.com
```

Ожидается перенаправление на HTTPS с кодом `301`.

Проверить HTTPS:

```bash
curl -Iv https://example.com
```

Домен `example.com` заменить на фактический домен приложения.

Убедиться, что HTTPS-запрос попадает в Spring Boot приложение.

## 8. Проверка сертификатов

На VPS:

```bash
certbot certificates
```

Проверить сроки действия сертификатов и соответствие доменов.

Проверить механизм продления:

```bash
systemctl status certbot.timer
```

Проверить продление в тестовом режиме:

```bash
certbot renew --dry-run
```

В данной конфигурации Certbot автоматически проверяет необходимость продления сертификатов.

Автоматический reload nginx после обновления сертификатов не настроен.

При необходимости выполнить вручную:

```bash
docker exec nginx nginx -s reload
```

## 9. Проверка файловых логов

Приложение использует Logback и записывает логи в `/app/logs`.

Docker Compose монтирует директорию VPS:

```text
/var/log/<APPLICATION> → /app/logs
```

Проверить наличие файлов:

```bash
ls -lh /var/log/<APPLICATION>
```

Посмотреть последние сообщения:

```bash
tail -n 100 /var/log/<APPLICATION>/<LOG_FILE>
```

`<LOG_FILE>` заменить на фактическое имя файла, заданное в конфигурации Logback.

В production используются:

- ConsoleAppender.
- RollingFileAppender.
- Ежедневная ротация файлов.
- Хранение истории за 7 дней.

## 10. Проверка полного цикла CI/CD

Для окончательной проверки выполнить изменение приложения.

### 10.1. Изменение исходного кода

В основном репозитории приложения внести небольшое изменение, результат которого можно проверить после развёртывания.

Например, изменить текст ответа существующего HTTP endpoint.

Не использовать для проверки изменения, которые могут нарушить работу приложения или повредить данные.

### 10.2. Публикация изменений

Для репозитория с основной веткой `master`:

```bash
git add .
git commit -m "chore: verify deployment pipeline"
git push origin master
```

Если основная ветка называется `main`, использовать её фактическое имя и соответствующий триггер GitHub Actions.

### 10.3. Проверка workflow

Открыть:

`GitHub → Actions → Build and Deploy`

Убедиться, что все шаги завершились успешно.

В логах шага деплоя ожидаются сообщения:

```text
Pulling latest images...
Restarting services...
Cleaning up old images...
Deploy finished successfully.
```

### 10.4. Проверка обновления приложения

На VPS:

```bash
cd /opt/<APPLICATION>-infra
docker compose ps
docker compose logs --tail=100 app
```

Проверить изменённый HTTP endpoint через публичный HTTPS-адрес.

Ожидается, что приложение возвращает новое значение, внесённое в исходный код.

Это подтверждает выполнение полной цепочки:

```text
git push
→ GitHub Actions
→ Docker build
→ GHCR
→ SSH
→ deploy.sh
→ Docker Compose
→ обновлённое приложение
```

## 11. Типовые проблемы

### GitHub Actions не запускается

Проверить:

- Наличие `.github/workflows/deploy.yml`.
- Название ветки в секции `on.push.branches`.
- Факт отправки коммита в соответствующую ветку.

### Ошибка сборки Docker-образа

Проверить:

- Dockerfile находится в корне основного репозитория.
- `pom.xml` и `src/` присутствуют.
- Maven успешно собирает приложение.
- Версия Java соответствует используемой приложением.

Подробная диагностика находится в логах `Build and push Docker image`.

### Ошибка публикации в GHCR

Проверить:

- `packages: write` в permissions.
- Корректность имени образа.
- Доступ GitHub Actions к публикации пакета.
- Логи шага `Log in to GHCR`.

### Ошибка SSH-подключения

Проверить:

- `VPS_HOST`.
- `VPS_USER`.
- `VPS_SSH_KEY`.
- Наличие соответствующего публичного ключа в `authorized_keys`.
- Доступность SSH-порта VPS.

### Ошибка скачивания Docker-образа

На VPS проверить:

```bash
docker pull ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

Если образ приватный, проверить авторизацию в GHCR.

Убедиться, что имя образа совпадает в GitHub Actions и Docker Compose.

### Контейнер приложения постоянно перезапускается

Проверить:

```bash
docker compose ps
docker compose logs --tail=200 app
```

Типовые причины:

- Ошибка конфигурации Spring Boot.
- Отсутствующая переменная окружения.
- Ошибка подключения к PostgreSQL.
- Ошибка запуска Java-приложения.

### Приложение не подключается к PostgreSQL

Проверить:

- Контейнер `db` запущен.
- PostgreSQL готов принимать подключения.
- URL использует имя сервиса `db`, а не `localhost`.
- Пользователь, пароль и имя БД соответствуют конфигурации.
- Приложение и PostgreSQL находятся в одной Docker-сети.

### nginx возвращает 502 Bad Gateway

Проверить:

```bash
curl -i http://127.0.0.1:8080
```

Если приложение недоступно, проверить контейнер и его логи.

Если приложение доступно, проверить `proxy_pass` в конфигурации nginx.

### HTTPS-сертификат не работает

Проверить:

```bash
certbot certificates
docker exec nginx nginx -t
```

Убедиться, что пути к сертификатам в nginx соответствуют файлам в `/etc/letsencrypt/live/`.

После обновления сертификата при необходимости выполнить:

```bash
docker exec nginx nginx -s reload
```

## 12. Ручной повторный деплой

Если образ уже опубликован в GHCR, повторный деплой можно выполнить вручную:

```bash
ssh root@<VPS_IP>
cd /opt/<APPLICATION>-infra
./deploy.sh
```

Скрипт скачивает актуальные образы и обновляет контейнеры.

Если требуется обновить инфраструктурную конфигурацию:

```bash
git pull origin main
./deploy.sh
```

Ветка должна соответствовать основной ветке infra-репозитория.

## Результат

Развёртывание считается завершённым, когда:

- GitHub Actions успешно собирает Docker-образ.
- Образ публикуется в GHCR.
- GitHub Actions подключается к VPS.
- `deploy.sh` выполняется успешно.
- Контейнеры приложения и PostgreSQL работают.
- Приложение успешно подключается к базе данных.
- nginx принимает HTTPS-запросы и проксирует их приложению.
- Логи приложения доступны на VPS.
- Изменение исходного кода после push автоматически появляется в работающем приложении.
