# Настройка nginx и HTTPS

## Назначение

Настройка HTTPS-доступа к Spring Boot приложению на VPS с использованием nginx и сертификатов Let's Encrypt.

nginx работает в отдельном Docker-контейнере с `network_mode: host`, принимает внешние HTTP/HTTPS-запросы и перенаправляет их на Spring Boot приложение.

Сертификаты выпускает и продлевает Certbot, установленный непосредственно на VPS.

## 1. Архитектура

```text
Client
  |
  | HTTPS :443
  v
VPS
  |
  | nginx (Docker, host network)
  |
  | proxy_pass http://127.0.0.1:8080
  v
Spring Boot (Docker)
  |
  v
PostgreSQL (Docker)
```

HTTP-запросы на порт 80 перенаправляются на HTTPS, кроме запросов Let's Encrypt для проверки владения доменом.

Компоненты:

- nginx — отдельный Docker-контейнер.
- Certbot — установлен на VPS.
- Сертификаты — `/etc/letsencrypt`.
- Конфигурации nginx — в отдельной директории на VPS.
- Spring Boot — доступен на `127.0.0.1:8080`.

Исходный код Java-приложения для настройки nginx не требуется.

## 2. Предварительные условия

Перед началом:

- VPS с Ubuntu 24.04 LTS.
- Установлены Docker и Docker Compose.
- Приложение уже запущено через Docker Compose.
- Приложение отвечает на `127.0.0.1:8080`.
- Есть домен, который будет использоваться для приложения.
- DNS-запись типа A для домена указывает на публичный IPv4-адрес VPS.
- Входящие TCP-подключения к портам 80 и 443 разрешены в настройках VPS, сетевого экрана и у хостинг-провайдера.

В примерах используется домен `example.com`. Его необходимо заменить на реальный.

Все команды выполняются на VPS под `root`, если не указано иное.

## 3. Подготовка директорий

Создать директорию для конфигурации nginx:

```bash
mkdir -p /opt/nginx-infra/nginx/conf.d
mkdir -p /opt/nginx-infra/nginx/webroot
```

Итоговая структура:

```text
/opt/nginx-infra/
├── docker-compose.yml
└── nginx/
    ├── conf.d/
    │   └── application.conf
    └── webroot/
```

Директория `webroot` используется для проверки владения доменом через HTTP-01 challenge Let's Encrypt.

## 4. Установка Certbot

Установить Certbot на VPS:

```bash
apt update
apt install -y certbot
```

Проверить установку:

```bash
certbot --version
```

Сертификаты будут храниться в `/etc/letsencrypt`.

## 5. Первоначальная конфигурация nginx

До выпуска сертификата необходимо запустить nginx без HTTPS-конфигурации, поскольку файлы сертификатов ещё не существуют.

Создать файл:

```text
/opt/nginx-infra/nginx/conf.d/application.conf
```

Содержимое:

```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}
```

В этом файле указан маршрут для проверки домена Let's Encrypt.

Все остальные HTTP-запросы перенаправляются на HTTPS.

До выпуска сертификата HTTPS ещё не будет работать.

## 6. Docker Compose для nginx

Создать файл:

```text
/opt/nginx-infra/docker-compose.yml
```

Содержимое:

```yaml
services:
  nginx:
    image: nginx:1.25-alpine
    container_name: nginx
    restart: unless-stopped
    network_mode: host
    volumes:
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/webroot:/var/www/certbot:ro
      - /etc/letsencrypt:/etc/letsencrypt:ro
```

`network_mode: host` позволяет nginx обращаться к приложениям через `127.0.0.1` сервера.

Монтирования:

- `conf.d` — конфигурации nginx.
- `webroot` — директория HTTP-01 challenge.
- `/etc/letsencrypt` — сертификаты и приватные ключи.

Монтирования выполняются в режиме `read-only`.

## 7. Запуск nginx

Перейти в директорию конфигурации:

```bash
cd /opt/nginx-infra
```

Запустить nginx:

```bash
docker compose up -d
```

Проверить контейнер:

```bash
docker compose ps
```

Проверить конфигурацию nginx:

```bash
docker exec nginx nginx -t
```

Ожидаемый результат:

```text
nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## 8. Выпуск HTTPS-сертификата

Для выпуска сертификата используется Certbot с методом `webroot`.

Выполнить на VPS:

```bash
certbot certonly --webroot \
  -w /opt/nginx-infra/nginx/webroot \
  -d example.com \
  -d www.example.com \
  --email admin@example.com \
  --agree-tos \
  --no-eff-email
```

Заменить домен и email на реальные значения.

Certbot создаёт проверочные файлы в `webroot`, а Let's Encrypt обращается к ним по HTTP через nginx.

После успешного выпуска сертификаты находятся в:

```text
/etc/letsencrypt/live/example.com/fullchain.pem
/etc/letsencrypt/live/example.com/privkey.pem
```

Проверить сертификаты:

```bash
certbot certificates
```

## 9. Настройка HTTPS

После выпуска сертификата заменить содержимое:

```text
/opt/nginx-infra/nginx/conf.d/application.conf
```

На:

```nginx
server {
    listen 80;
    server_name example.com www.example.com;

    location ^~ /.well-known/acme-challenge/ {
        root /var/www/certbot;
        default_type "text/plain";
        try_files $uri =404;
    }

    location / {
        return 301 https://$host$request_uri;
    }
}

server {
    listen 443 ssl;
    server_name example.com www.example.com;

    ssl_certificate /etc/letsencrypt/live/example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/example.com/privkey.pem;

    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_prefer_server_ciphers off;

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;

        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;

        proxy_read_timeout 60s;
        proxy_connect_timeout 10s;
    }
}
```

Объяснение:

- `listen 80` — HTTP и перенаправление на HTTPS.
- `listen 443 ssl` — HTTPS.
- `ssl_certificate` — публичный сертификат и цепочка доверия.
- `ssl_certificate_key` — приватный ключ сертификата.
- `proxy_pass` — адрес Spring Boot приложения на VPS.
- `X-Forwarded-*` — передача информации об исходном запросе приложению.

Поскольку nginx работает с `network_mode: host`, он использует `127.0.0.1:8080` для обращения к приложению.

## 10. Применение конфигурации

Проверить синтаксис nginx:

```bash
docker exec nginx nginx -t
```

Перезагрузить конфигурацию без остановки контейнера:

```bash
docker exec nginx nginx -s reload
```

Проверить HTTPS:

```bash
curl -I https://example.com
```

Проверить HTTP-redirect:

```bash
curl -I http://example.com
```

Ожидается перенаправление на HTTPS с кодом `301`.

Ответ на HTTPS-запрос зависит от маршрутов Spring Boot приложения.

## 11. Автоматическое продление сертификатов

Certbot на Ubuntu использует systemd timer для периодической проверки сертификатов.

Проверить таймер:

```bash
systemctl list-timers --all | grep certbot
```

Проверить статус:

```bash
systemctl status certbot.timer
```

Если таймер выключен:

```bash
systemctl enable --now certbot.timer
```

Проверить продление без замены действующих сертификатов:

```bash
certbot renew --dry-run
```

После обновления сертификата nginx должен перечитать новые файлы.

В данной схеме автоматический reload nginx не настраивается. При необходимости его можно выполнить вручную:

```bash
docker exec nginx nginx -s reload
```

Сам Certbot обновляет файлы сертификатов на VPS, но nginx может продолжать использовать прежний сертификат, пока его конфигурация не будет перезагружена.

## 12. Добавление дополнительных приложений

Один nginx может обслуживать несколько приложений на одном VPS.

Для этого каждое приложение публикуется на отдельном localhost-порту:

```text
Application A → 127.0.0.1:8080
Application B → 127.0.0.1:8081
Application C → 127.0.0.1:8082
```

В каталоге `/opt/nginx-infra/nginx/conf.d/` создаются отдельные конфигурации.

Каждая конфигурация определяет:

- Домен приложения.
- Сертификат.
- Локальный порт приложения.
- Правила проксирования.

Для нового домена необходимо настроить DNS, выпустить сертификат через Certbot и добавить соответствующий HTTPS server block.

После изменения конфигурации:

```bash
docker exec nginx nginx -t
docker exec nginx nginx -s reload
```

## 13. Диагностика

Проверить состояние nginx:

```bash
docker ps
```

Посмотреть логи:

```bash
docker logs nginx --tail 100
```

Проверить конфигурацию:

```bash
docker exec nginx nginx -t
```

Проверить доступность Spring Boot непосредственно на VPS:

```bash
curl -i http://127.0.0.1:8080
```

Проверить сертификаты:

```bash
certbot certificates
```

Проверить обновление:

```bash
certbot renew --dry-run
```

Проверить HTTPS:

```bash
curl -Iv https://example.com
```

Если nginx возвращает `502 Bad Gateway`, проверить, запущено ли приложение и соответствует ли `proxy_pass` опубликованному порту приложения.

## Результат

- nginx запущен в отдельном Docker-контейнере.
- nginx использует host network.
- Spring Boot доступен через HTTPS.
- HTTP-запросы перенаправляются на HTTPS.
- Сертификаты Let's Encrypt хранятся на VPS.
- Certbot настроен на периодическое продление сертификатов.
- Конфигурация позволяет обслуживать несколько приложений на одном сервере.

Следующий этап: [Проверка развёртывания](08-verification.md).
