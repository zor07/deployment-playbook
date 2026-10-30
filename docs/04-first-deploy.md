# Первоначальное развёртывание приложения на VPS

## Назначение

Первоначальный ручной деплой Spring Boot приложения и PostgreSQL на VPS с Ubuntu 24.04 LTS с использованием Docker Compose и GitHub Container Registry (GHCR).

На этом этапе автоматический деплой через GitHub Actions ещё не настраивается.

## 1. Предварительные условия

Перед началом должны быть подготовлены:

- VPS с Ubuntu 24.04 LTS.
- Установленные Docker Engine, Docker Compose и Git.
- SSH-доступ к VPS под пользователем `root`.
- GitHub-репозиторий `<APPLICATION>-infra` с файлами `docker-compose.yml`, `deploy.sh`, `.env.example`, `.gitignore`.
- Docker-образ приложения `ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest`, опубликованный в GHCR.

Если Docker-образ ещё не опубликован, сначала необходимо выполнить сборку и публикацию образа согласно [настройке CI](05-github-actions-ci.md).

Все команды этого документа, если не указано иное, выполняются на VPS.

Значения `<APPLICATION>`, `<GITHUB_USERNAME>` и другие параметры в угловых скобках необходимо заменить на реальные.

## 2. Настройка SSH-доступа VPS к GitHub

Для клонирования приватного инфраструктурного репозитория настроить SSH-ключ.

Создать ключ на VPS:

```bash
ssh-keygen -t ed25519 -C "vps-github" -f ~/.ssh/github_deploy
```

Вывести публичную часть:

```bash
cat ~/.ssh/github_deploy.pub
```

Добавить публичный ключ в GitHub-репозиторий `<APPLICATION>-infra`:

`Settings → Deploy keys → Add deploy key`

Право `Allow write access` не требуется.

Создать или дополнить `/root/.ssh/config`:

```sshconfig
Host github.com
    HostName github.com
    User git
    IdentityFile ~/.ssh/github_deploy
    IdentitiesOnly yes
```

Установить права:

```bash
chmod 600 /root/.ssh/config
chmod 600 /root/.ssh/github_deploy
```

При первом SSH-подключении проверить подлинность ключа хоста GitHub по официально опубликованным fingerprint и подтвердить его сохранение в `known_hosts`.

Проверить подключение:

```bash
ssh -T git@github.com
```

При успешной авторизации GitHub сообщает об успешной аутентификации без предоставления shell-доступа. Ненулевой код завершения этой команды сам по себе не означает ошибку авторизации.

## 3. Клонирование инфраструктурного репозитория

Создать директорию приложений и клонировать infra-репозиторий:

```bash
mkdir -p /opt
cd /opt
git clone git@github.com:<GITHUB_USERNAME>/<APPLICATION>-infra.git
cd <APPLICATION>-infra
```

На VPS клонируется только инфраструктурный репозиторий. Исходный Java-код не требуется, поскольку приложение запускается из готового Docker-образа.

## 4. Настройка переменных окружения

Создать рабочий `.env`:

```bash
cp .env.example .env
nano .env
```

Пример содержимого:

```dotenv
DB_URL=jdbc:postgresql://db:5432/bot_db
DB_NAME=bot_db
DB_USERNAME=user
DB_PASSWORD=<DB_PASSWORD>
```

Значения должны соответствовать настройкам Spring Boot и PostgreSQL в Docker Compose.

Установить права:

```bash
chmod 600 .env
```

Файл `.env` хранится только на VPS и не добавляется в Git.

## 5. Подготовка логирования

Создать директорию для файловых логов приложения:

```bash
mkdir -p /var/log/<APPLICATION>
```

В `docker-compose.yml` используется bind mount:

```text
VPS:       /var/log/<APPLICATION>
Container: /app/logs
```

Logback пишет файлы в `/app/logs`, а Docker сохраняет их в соответствующей директории VPS.

Права на запись в директорию должны соответствовать пользователю, под которым работает Java-приложение внутри контейнера.

## 6. Авторизация в GHCR

Для скачивания приватных Docker-образов используется GitHub Personal Access Token (classic) с разрешением `read:packages`.

Авторизоваться на VPS:

```bash
docker login ghcr.io -u <GITHUB_USERNAME>
```

При запросе пароля указать PAT.

Токен не следует передавать непосредственно в командной строке или сохранять в репозитории.

Для публичных Docker-образов авторизация может не требоваться.

## 7. Первый запуск

Находясь в `/opt/<APPLICATION>-infra`, выполнить:

```bash
chmod +x deploy.sh
docker compose pull
docker compose up -d
```

Docker Compose выполняет следующие действия:

1. Скачивает образы приложения и PostgreSQL.
2. Создаёт сеть контейнеров.
3. Создаёт named volume для хранения данных PostgreSQL.
4. Передаёт переменные окружения.
5. Запускает контейнеры приложения и базы данных.

Приложение подключается к PostgreSQL по имени сервиса `db` и внутреннему порту `5432`.

Параметр `depends_on` определяет порядок запуска, но не гарантирует готовность PostgreSQL к приёму соединений.

## 8. Проверка развёртывания

Проверить состояние контейнеров:

```bash
docker compose ps
```

Посмотреть последние сообщения приложения:

```bash
docker compose logs --tail=100 app
```

Проверить доступность приложения:

```bash
curl -i http://127.0.0.1:8080
```

HTTP-статус зависит от реализованных endpoint и настроек Spring Security. Например, ответ `404` на корневой маршрут не обязательно означает ошибку запуска приложения.

Проверить PostgreSQL:

```bash
docker compose exec db pg_isready -U user -d bot_db
```

Проверить файлы логов:

```bash
ls -lh /var/log/<APPLICATION>
```

Успешный результат — оба контейнера работают, приложение подключается к PostgreSQL и отвечает на HTTP-запросы.

## 9. Ручной деплой новой версии

После публикации нового Docker-образа в GHCR перейти в infra-репозиторий:

```bash
cd /opt/<APPLICATION>-infra
./deploy.sh
```

Скрипт выполняет:

```bash
docker compose pull
docker compose up -d
docker image prune -f
```

При изменении файлов самого инфраструктурного репозитория предварительно обновить его:

```bash
git pull origin main
```

`deploy.sh` не выполняет `git pull` самостоятельно.

## 10. Управление контейнерами

Остановить и удалить контейнеры:

```bash
docker compose down
```

Повторно запустить:

```bash
docker compose up -d
```

Перезапустить только приложение:

```bash
docker compose restart app
```

Посмотреть логи в реальном времени:

```bash
docker compose logs -f app
```

При обычном `docker compose down` named volume PostgreSQL сохраняется.

Команда `docker compose down -v` удаляет также volumes проекта, включая данные PostgreSQL.

## Результат

- Приложение и PostgreSQL работают в отдельных Docker-контейнерах.
- Образ приложения скачивается из GHCR.
- VPS не содержит исходного Java-кода.
- Данные PostgreSQL сохраняются в Docker volume.
- Файловые логи доступны на VPS.
- Приложение доступно через `127.0.0.1:8080`.
- Ручное обновление выполняется через `deploy.sh`.

Следующий этап: [Настройка GitHub Actions CI](05-github-actions-ci.md).
