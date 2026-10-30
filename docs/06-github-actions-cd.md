# Настройка GitHub Actions CD

## Назначение

Настройка автоматического развёртывания Spring Boot приложения на VPS после успешной сборки и публикации Docker-образа в GitHub Container Registry (GHCR).

Используется существующая схема:

```text
git push → master
    |
    v
GitHub Actions
    |
    ├── Checkout
    ├── Docker build
    ├── Push → GHCR (:latest)
    |
    └── SSH → VPS
                 |
                 v
            git pull (infra)
                 |
                 v
            deploy.sh
                 |
                 ├── docker compose pull
                 ├── docker compose up -d
                 └── docker image prune -f
```

Исходный код приложения не копируется на VPS. Сервер использует готовый Docker-образ и отдельный инфраструктурный репозиторий.

## 1. Предварительные условия

Перед настройкой CD должны быть выполнены предыдущие этапы:

- Настроен CI для сборки и публикации образа в GHCR.
- На VPS установлены Docker Engine и Docker Compose.
- Инфраструктурный репозиторий клонирован в `/opt/<APPLICATION>-infra`.
- Создан `.env` с необходимыми переменными окружения.
- VPS имеет доступ к GitHub для обновления infra-репозитория.
- VPS имеет доступ к GHCR для скачивания Docker-образов.
- Приложение и PostgreSQL успешно запускаются вручную через Docker Compose.
- Скрипт `deploy.sh` находится в корне infra-репозитория.

Настройка GitHub Actions выполняется в **основном репозитории приложения**, не в infra-репозитории.

## 2. Создание SSH-ключа для GitHub Actions

Для подключения GitHub Actions к VPS используется отдельная пара SSH-ключей.

Создать ключ на локальном компьютере:

```bash
ssh-keygen -t ed25519 -C "github-actions-deploy" -f ~/.ssh/github_actions_deploy
```

Будут созданы:

```text
~/.ssh/github_actions_deploy
~/.ssh/github_actions_deploy.pub
```

Приватный ключ используется GitHub Actions. Публичный ключ добавляется на VPS.

Для автоматического подключения в данной схеме ключ создаётся без passphrase.

## 3. Добавление публичного ключа на VPS

На локальном компьютере вывести публичный ключ:

```bash
cat ~/.ssh/github_actions_deploy.pub
```

Подключиться к VPS:

```bash
ssh root@<VPS_IP>
```

Подготовить SSH-директорию:

```bash
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
```

Добавить публичный ключ отдельной строкой в:

```text
/root/.ssh/authorized_keys
```

Например, открыть файл:

```bash
nano /root/.ssh/authorized_keys
```

Существующие ключи не удалять.

В данной конфигурации GitHub Actions подключается к VPS под пользователем `root`.

## 4. Проверка SSH-подключения

На локальном компьютере проверить подключение с использованием созданного ключа:

```bash
ssh -i ~/.ssh/github_actions_deploy root@<VPS_IP>
```

Подключение должно выполняться без запроса пароля пользователя VPS.

Если приватный ключ защищён passphrase, SSH может запросить её. В предлагаемом workflow отдельная передача passphrase не настроена.

## 5. Настройка GitHub Secrets

Открыть основной GitHub-репозиторий приложения:

```text
Settings
  → Secrets and variables
  → Actions
  → New repository secret
```

Добавить три секрета:

| Secret | Значение |
|---|---|
| `VPS_HOST` | Публичный IP-адрес или домен VPS |
| `VPS_USER` | `root` |
| `VPS_SSH_KEY` | Содержимое приватного SSH-ключа |

Содержимое приватного ключа получить на локальном компьютере:

```bash
cat ~/.ssh/github_actions_deploy
```

Скопировать полный ключ, включая строки `BEGIN OPENSSH PRIVATE KEY` и `END OPENSSH PRIVATE KEY`, в GitHub Secret `VPS_SSH_KEY`.

Приватный ключ не добавлять в Git-репозиторий и не передавать другим пользователям.

Секрет `GITHUB_TOKEN` создавать вручную не требуется — GitHub Actions предоставляет его автоматически.

## 6. Обновление GitHub Actions workflow

В основном репозитории приложения открыть файл:

```text
.github/workflows/deploy.yml
```

Заменить его содержимое:

```yaml
name: Build and Deploy

on:
  push:
    branches: [master]

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Log in to GHCR
        uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}

      - name: Build and push Docker image
        uses: docker/build-push-action@v5
        with:
          context: .
          push: true
          tags: ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest

      - name: Deploy on VPS
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ secrets.VPS_HOST }}
          username: ${{ secrets.VPS_USER }}
          key: ${{ secrets.VPS_SSH_KEY }}
          script: |
            cd /opt/<APPLICATION>-infra
            git pull origin main
            ./deploy.sh
```

Заменить `<GITHUB_USERNAME>` и `<APPLICATION>` на реальные значения.

Если основная ветка репозитория приложения называется `main`, заменить `master` на `main` в триггере.

Если infra-репозиторий использует ветку `master`, заменить `git pull origin main` на `git pull origin master`.

## 7. Выполнение автоматического деплоя

После успешной публикации Docker-образа выполняется шаг:

```yaml
- name: Deploy on VPS
  uses: appleboy/ssh-action@v1.0.3
  with:
    host: ${{ secrets.VPS_HOST }}
    username: ${{ secrets.VPS_USER }}
    key: ${{ secrets.VPS_SSH_KEY }}
    script: |
      cd /opt/<APPLICATION>-infra
      git pull origin main
      ./deploy.sh
```

Последовательность:

1. GitHub Actions подключается к VPS по SSH.
2. Переходит в директорию инфраструктурного репозитория.
3. Обновляет infra-репозиторий через `git pull`.
4. Запускает `deploy.sh`.

Скрипт `deploy.sh` выполняет:

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

`docker compose pull` скачивает актуальные образы.

`docker compose up -d` приводит контейнеры к состоянию, определённому конфигурацией Compose. Если образ приложения обновился, контейнер приложения пересоздаётся.

`docker image prune -f` удаляет неиспользуемые Docker-образы.

Данные PostgreSQL хранятся в named volume и сохраняются при обычном обновлении контейнеров.

## 8. Проверка автоматического деплоя

В основном репозитории приложения выполнить изменение и отправить его в ветку, указанную в триггере workflow.

Например, для `master`:

```bash
git add .
git commit -m "chore: verify automatic deployment"
git push origin master
```

Открыть:

```text
GitHub → Repository → Actions → Build and Deploy
```

Проверить успешное выполнение:

1. Checkout.
2. Log in to GHCR.
3. Build and push Docker image.
4. Deploy on VPS.

На VPS проверить контейнеры:

```bash
cd /opt/<APPLICATION>-infra
docker compose ps
```

Проверить логи приложения:

```bash
docker compose logs --tail=100 app
```

Проверить доступность приложения:

```bash
curl -i http://127.0.0.1:8080
```

Конкретный HTTP-статус зависит от маршрутов приложения.

## 9. Ручной деплой

Автоматический деплой не исключает возможность ручного обновления.

Подключиться к VPS:

```bash
ssh root@<VPS_IP>
```

Перейти в инфраструктурный репозиторий:

```bash
cd /opt/<APPLICATION>-infra
```

При необходимости обновить инфраструктурные конфигурации:

```bash
git pull origin main
```

Запустить деплой:

```bash
./deploy.sh
```

Это выполняет те же операции Docker Compose, что и автоматический деплой.

## Результат

После настройки CD:

- Push в основную ветку приложения запускает GitHub Actions.
- Docker-образ автоматически собирается и публикуется в GHCR.
- GitHub Actions подключается к VPS по SSH.
- Infra-репозиторий обновляется через Git.
- `deploy.sh` скачивает актуальные образы и обновляет контейнеры.
- PostgreSQL сохраняет данные в Docker volume.
- На VPS отсутствуют исходники Java-приложения.

Следующий этап: [Настройка nginx и HTTPS](07-nginx-https.md).
