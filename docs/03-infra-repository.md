# Подготовка инфраструктурного репозитория

## Назначение

Создать отдельный GitHub-репозиторий `<application>-infra` для развёртывания Spring Boot приложения на VPS.

| Расположение | Содержимое |
| --- | --- |
| Основной репозиторий приложения | Java-код, Maven, Dockerfile, GitHub Actions и конфигурация Logback |
| Инфраструктурный репозиторий | Docker Compose, `deploy.sh`, шаблон переменных окружения и `.gitignore` |
| VPS | Клон инфраструктурного репозитория, рабочий `.env`, Docker-образы и данные контейнеров |

На VPS клонируется только инфраструктурный репозиторий. Исходники Java там отсутствуют. Docker Compose использует готовый образ из GHCR; на VPS приложение не собирается.

Команды подготовки файлов и публикации выполняются **локально**, в клоне инфраструктурного репозитория. Репозиторий `deployment-playbook` содержит только документацию и примеры.

## 1. Создание репозитория

В GitHub создайте пустой репозиторий `<application>-infra` без README, лицензии и автоматически созданного `.gitignore`.

Замените `<GITHUB_USERNAME>` на владельца репозитория, `<application>` — на имя приложения. В Compose замените `<GITHUB_USERNAME>` и `<APPLICATION>` фактическими значениями в нижнем регистре: путь образа должен совпадать с публикуемым пакетом GHCR. Угловые скобки также удаляются. Эти параметры автоматически не подставляются.

**Локально:**

```bash
git clone git@github.com:<GITHUB_USERNAME>/<application>-infra.git
cd <application>-infra
```

Сообщение о клонировании пустого репозитория ожидаемо. Создайте в корне четыре файла:

```text
application-infra/
├── docker-compose.yml
├── deploy.sh
├── .env.example
└── .gitignore
```

`application-infra` — условное имя каталога `<application>-infra`. Рабочий `.env` создаётся отдельно и не попадает в Git.

## 2. Docker Compose

Создайте `docker-compose.yml`:

```yaml
services:
  app:
    image: ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
    restart: unless-stopped
    ports:
      - "127.0.0.1:8080:8080"
    env_file:
      - .env
    environment:
      SPRING_PROFILES_ACTIVE: prod
    volumes:
      - /var/log/<APPLICATION>:/app/logs
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    restart: unless-stopped
    ports:
      - "127.0.0.1:5432:5432"
    environment:
      POSTGRES_DB: ${DB_NAME}
      POSTGRES_USER: ${DB_USERNAME}
      POSTGRES_PASSWORD: ${DB_PASSWORD}
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

| Параметр | Назначение |
| --- | --- |
| `image` | Готовый образ приложения из GHCR с тегом `latest`; для БД — `postgres:16-alpine`. Секции `build` нет |
| `restart: unless-stopped` | Перезапуск контейнера при завершении и после перезапуска Docker, если контейнер не был явно остановлен |
| `ports` | Порты приложения и PostgreSQL привязаны только к loopback VPS. nginx на VPS сможет обращаться к `127.0.0.1:8080`; напрямую через публичный IP эти порты недоступны |
| `env_file` | Передаёт значения из `.env` в окружение контейнера приложения |
| `environment` | Задаёт профиль `prod` для Spring Boot и параметры инициализации PostgreSQL |
| `volumes` у `app` | Монтирует каталог логов VPS в `/app/logs` контейнера |
| `depends_on` | Запускает `db` перед `app`, но не гарантирует готовность PostgreSQL принимать подключения |
| `pgdata` | Named volume с данными PostgreSQL, смонтированный в `/var/lib/postgresql/data` |

Named volume сохраняется при пересоздании контейнера и при `docker compose down`. Команда `docker compose down -v` удаляет его вместе с данными БД.

## 3. Переменные окружения

Создайте `.env.example`:

```ini
DB_URL=jdbc:postgresql://db:5432/bot_db
DB_NAME=bot_db
DB_USERNAME=user
DB_PASSWORD=change_me
```

Приложение должно читать `DB_URL`, `DB_USERNAME`, `DB_PASSWORD` через настройки Spring Boot, как описано в [локальной контейнеризации](01-local-docker.md).

Создайте рабочий файл:

```bash
cp .env.example .env
chmod 600 .env
```

Перед запуском замените `change_me` в `.env` на пароль окружения. Если меняете `DB_NAME`, синхронно измените имя БД в `DB_URL`. Адрес `db:5432` относится к внутренней сети Compose и не заменяется на `localhost`.

Compose читает `.env` для подстановок `${DB_NAME}`, `${DB_USERNAME}`, `${DB_PASSWORD}` в конфигурацию `db`; `env_file` отдельно передаёт значения приложению. Экспортированные переменные оболочки имеют приоритет при подстановке: не допускайте расхождения с `.env`. Подробнее — [переменные Compose](https://docs.docker.com/compose/how-tos/environment-variables/variable-interpolation/).

`POSTGRES_DB`, `POSTGRES_USER` и `POSTGRES_PASSWORD` инициализируют БД при первом запуске с пустым volume. Изменение `.env` после инициализации не меняет существующих пользователей, пароли или базы данных.

## 4. Gitignore

Создайте `.gitignore`:

```gitignore
.env
```

В Git публикуется только `.env.example` с шаблонными значениями. Рабочий `.env` с паролем остаётся вне Git; на VPS его потребуется создать отдельно.

## 5. Скрипт деплоя

Создайте `deploy.sh`:

```bash
#!/usr/bin/env bash
set -e

echo "Pulling latest images..."
docker compose pull

echo "Restarting services..."
docker compose up -d

echo "Cleaning up old images..."
docker image prune -f

echo "Deploy finished successfully."
```

Сделайте скрипт исполняемым:

```bash
chmod +x deploy.sh
```

Назначение команд:

- `#!/usr/bin/env bash` выбирает Bash для выполнения скрипта.
- `set -e` прекращает выполнение при ошибке команды.
- `docker compose pull` скачивает актуальные образы сервисов, включая приложение с тегом `latest`.
- `docker compose up -d` создаёт или обновляет контейнеры и запускает их в фоне, используя существующий volume PostgreSQL.
- `docker image prune -f` без подтверждения удаляет неиспользуемые образы без тегов на Docker-хосте. Команда не ограничена текущим Compose-проектом.
- `echo` выводит этапы выполнения и сообщение об успешном завершении команд.

Скрипт запускается из корня инфраструктурного репозитория, где находятся `docker-compose.yml` и рабочий `.env`. При последующем деплое **на VPS** это будет:

```bash
cd /opt/<application>-infra
./deploy.sh
```

На этом этапе скрипт не запускайте: сначала необходимо опубликовать образ, подготовить `.env` и доступ к GHCR. Успешное завершение скрипта означает выполнение команд Docker, а не проверку HTTP-доступности или готовности приложения.

## 6. Логирование

Монтирование `/var/log/<APPLICATION>:/app/logs` связывает каталог VPS с каталогом логов приложения. После замены `<APPLICATION>` файлы из `/app/logs` сохраняются на хосте и переживают пересоздание контейнера. При первом деплое каталог хоста должен быть доступен на запись пользователю контейнера.

В **основном репозитории приложения** разместите [пример `logback-spring.xml`](../examples/logback-spring.xml) по пути `src/main/resources/logback-spring.xml`. Файл включается в JAR и Docker-образ приложения; в инфраструктурном репозитории он отсутствует.

Конфигурация использует `ConsoleAppender` для консоли. В профиле `prod` дополнительно включается `RollingFileAppender`, записывающий `/app/logs/application.log`; в профиле `!prod` остаётся только консоль. Профиль `prod` задаётся через `SPRING_PROFILES_ACTIVE` в Compose. Поддержка профилей требует имени `logback-spring.xml`; см. [документацию Spring Boot](https://docs.spring.io/spring-boot/reference/features/logging.html#features.logging.logback-extensions).

`TimeBasedRollingPolicy` с шаблоном `application.%d{yyyy-MM-dd}.log.gz` обеспечивает ежедневную ротацию с архивированием. `maxHistory=7` ограничивает историю семью дневными периодами; текущий файл хранится отдельно. Ротация выполняется при поступлении события после смены дня. `cleanHistoryOnStart=true` включает очистку старых архивов также при запуске приложения.

Для локального запуска используйте Compose из [раздела 01](01-local-docker.md). Файл `examples/docker-compose.yml` в `deployment-playbook` теперь содержит production-конфигурацию для этого и следующих этапов.

## 7. Публикация

**Локально, в корне инфраструктурного репозитория:**

```bash
git check-ignore .env
git status --short
```

Первая команда должна вывести `.env`. Рабочий файл не должен присутствовать среди файлов для коммита. Опубликуйте четыре инфраструктурных файла:

```bash
git add docker-compose.yml deploy.sh .env.example .gitignore
git commit -m "chore: initialize application infrastructure"
git branch -M main
git push -u origin main
```

Результат: отдельный инфраструктурный репозиторий опубликован в GitHub. В нём нет исходников Java, Dockerfile или рабочего `.env`. Клонирование на VPS, доступ к GHCR и первый запуск выполняются на следующем этапе.

Следующий раздел: [Первоначальный деплой](04-first-deploy.md).
