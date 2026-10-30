# Настройка GitHub Actions CI

## Назначение

Настройка автоматической сборки Docker-образа Spring Boot приложения и его публикации в GitHub Container Registry (GHCR).

После каждого push в ветку `master` GitHub Actions собирает Docker-образ приложения и публикует его с тегом `latest`.

На этом этапе настраивается только CI. Автоматическое развёртывание на VPS рассматривается в следующем разделе.

## 1. Предварительные условия

Перед началом:

- Основной GitHub-репозиторий приложения существует.
- В корне основного репозитория находится `Dockerfile`.
- Приложение использует Java 21, Spring Boot и Maven.
- Dockerfile успешно используется для локальной сборки приложения.
- Есть доступ к настройкам GitHub-репозитория.

Все действия выполняются **в основном репозитории приложения**, а не в инфраструктурном репозитории.

В данном руководстве используется ветка `master` как ветка, запускающая CI/CD. Если основная ветка приложения называется `main`, необходимо заменить `master` на `main` в настройках workflow.

## 2. Создание GitHub Actions workflow

В корне основного репозитория приложения создать директорию:

```bash
mkdir -p .github/workflows
```

Создать файл:

```text
.github/workflows/deploy.yml
```

Содержимое:

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
```

Заменить:

- `<GITHUB_USERNAME>` — имя пользователя или организации GitHub.
- `<APPLICATION>` — название Docker-образа приложения.

Итоговое имя образа должно совпадать со значением `image` в `docker-compose.yml` инфраструктурного репозитория.

## 3. Как работает workflow

### Триггер

```yaml
on:
  push:
    branches: [master]
```

Workflow автоматически запускается после push в ветку `master`.

### GitHub Runner

```yaml
runs-on: ubuntu-latest
```

GitHub предоставляет временное окружение Ubuntu для выполнения сборки.

### Разрешения

```yaml
permissions:
  contents: read
  packages: write
```

- `contents: read` — доступ на чтение исходного кода.
- `packages: write` — разрешение публиковать Docker-образы в GHCR.

### Checkout

```yaml
- name: Checkout
  uses: actions/checkout@v4
```

Загружает исходный код репозитория в рабочее окружение GitHub Actions.

### Авторизация в GHCR

```yaml
- name: Log in to GHCR
  uses: docker/login-action@v3
  with:
    registry: ghcr.io
    username: ${{ github.actor }}
    password: ${{ secrets.GITHUB_TOKEN }}
```

Авторизация выполняется через встроенный `GITHUB_TOKEN`.

Создавать отдельный Personal Access Token для публикации образа в рамках этого workflow не требуется.

### Сборка и публикация

```yaml
- name: Build and push Docker image
  uses: docker/build-push-action@v5
  with:
    context: .
    push: true
    tags: ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

GitHub Actions:

1. Использует Dockerfile из корня репозитория.
2. Собирает Docker-образ приложения.
3. Авторизуется в GHCR.
4. Публикует образ с тегом `latest`.

Исходный Java-код не передаётся на VPS. На сервер в дальнейшем скачивается готовый Docker-образ.

## 4. Настройка GitHub Packages

После первой успешной публикации Docker-образ появится в GitHub Packages.

Проверить его можно через интерфейс GitHub в разделе Packages пользователя или организации.

Имя образа:

```text
ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

Если образ приватный, для скачивания с VPS потребуется авторизация в GHCR, описанная в `04-first-deploy.md`.

Если образ публичный, его можно скачивать без авторизации.

Для публикации пакета workflow должен иметь соответствующие права. Если GitHub возвращает ошибку доступа, проверить права `GITHUB_TOKEN`, принадлежность пакета и его настройки доступа.

## 5. Проверка CI

Отправить изменение в ветку `master` основного репозитория приложения:

```bash
git add .
git commit -m "chore: configure CI"
git push origin master
```

Открыть GitHub:

```text
Repository → Actions → Build and Deploy
```

Проверить успешное выполнение шагов:

1. Checkout.
2. Log in to GHCR.
3. Build and push Docker image.

После успешного выполнения проверить наличие опубликованного Docker-образа в GHCR.

## 6. Проверка опубликованного образа

На компьютере с установленным Docker:

```bash
docker pull ghcr.io/<GITHUB_USERNAME>/<APPLICATION>:latest
```

Для приватного образа предварительно потребуется авторизация:

```bash
docker login ghcr.io -u <GITHUB_USERNAME>
```

Проверить локально скачанный образ:

```bash
docker images
```

Если образ успешно скачивается, публикация в GHCR работает.

## 7. Обновление образа

При следующем push в `master` workflow снова выполнит сборку и публикацию.

Образ будет опубликован с тем же тегом:

```text
latest
```

На данном этапе новая версия автоматически на VPS не разворачивается.

Для обновления приложения пока используется ручной запуск `deploy.sh` на VPS.

## Результат

- GitHub Actions запускается при push в `master`.
- Docker-образ приложения собирается автоматически.
- Авторизация в GHCR выполняется через `GITHUB_TOKEN`.
- Docker-образ публикуется с тегом `latest`.
- Образ доступен для скачивания на VPS.
- CI не зависит от инфраструктурного репозитория.

Следующий этап: [Настройка GitHub Actions CD](06-github-actions-cd.md).
