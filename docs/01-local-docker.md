# Локальная контейнеризация приложения

## Назначение

Сборка Docker-образа Spring Boot приложения и локальный запуск приложения совместно с PostgreSQL через Docker Compose.

Технологический стек: Java 21, Maven, Spring Boot, PostgreSQL.

Все действия выполняются **в основном репозитории приложения**, где находятся `pom.xml` и исходный код в `src/`.

На этом этапе файлы `Dockerfile` и `docker-compose.yml` создаются в корне основного репозитория приложения. Инфраструктурный репозиторий пока не используется.

## 1. Dockerfile

В корне основного репозитория приложения создать `Dockerfile`:

```dockerfile
FROM maven:3.9-eclipse-temurin-21 AS build

WORKDIR /app
COPY pom.xml .
COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:21-jre

WORKDIR /app
COPY --from=build /app/target/*.jar app.jar

EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Используется двухэтапная сборка: Maven собирает исполняемый JAR, после чего он переносится в образ с Java Runtime.

Предполагается, что Maven формирует один исполняемый Spring Boot JAR в `target/`.

## 2. Конфигурация PostgreSQL

В конфигурации Spring Boot задать подключение через переменные окружения:

```properties
spring.datasource.url=${DB_URL}
spring.datasource.username=${DB_USERNAME}
spring.datasource.password=${DB_PASSWORD}
```

Эти значения передаются приложению через Docker Compose.

## 3. Docker Compose

В корне основного репозитория приложения создать `docker-compose.yml`:

```yaml
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      DB_URL: jdbc:postgresql://db:5432/bot_db
      DB_USERNAME: user
      DB_PASSWORD: pass
    depends_on:
      - db

  db:
    image: postgres:16-alpine
    environment:
      POSTGRES_DB: bot_db
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
    ports:
      - "5432:5432"
    volumes:
      - pgdata:/var/lib/postgresql/data

volumes:
  pgdata:
```

`app` и `db` — имена сервисов Docker Compose.

Приложение подключается к PostgreSQL по адресу `db:5432`, используя внутреннюю сеть Docker Compose.

Данные PostgreSQL сохраняются в named volume `pgdata`.

Учётные данные в примере предназначены только для локального окружения.

`depends_on` определяет порядок запуска контейнеров, но не гарантирует готовность PostgreSQL к приёму подключений.

## 4. Сборка и запуск

Из корня основного репозитория приложения:

```bash
docker compose up -d --build
```

Docker Compose собирает образ приложения, создаёт необходимые контейнеры и запускает их в фоновом режиме.

## 5. Проверка

Проверить состояние контейнеров:

```bash
docker compose ps
```

Посмотреть логи:

```bash
docker compose logs -f app
```

Проверить HTTP-доступность приложения:

```bash
curl -i http://localhost:8080
```

Конкретный HTTP-статус зависит от реализованных endpoint и конфигурации Spring Security.

Убедиться по логам, что Spring Boot успешно запустился и установил подключение к PostgreSQL.

## 6. Повторная сборка

После изменения исходного кода:

```bash
docker compose up -d --build
```

Полная пересборка без использования кеша:

```bash
docker compose build --no-cache
docker compose up -d
```

## 7. Остановка

Остановить и удалить контейнеры:

```bash
docker compose down
```

Данные PostgreSQL в named volume сохраняются.

Команда `docker compose down -v` удаляет также volumes проекта, включая данные PostgreSQL.

## Результат

Spring Boot и PostgreSQL запускаются локально в Docker.

Приложение успешно подключается к базе данных и доступно на `localhost:8080`.
