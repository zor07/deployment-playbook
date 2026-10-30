# Первоначальная настройка VPS

## Назначение

Подготовка чистого VPS с Ubuntu 24.04 LTS для запуска Java-приложений через Docker Compose.

Исходные условия:

- Установлена Ubuntu Server 24.04 LTS, 64-битная версия.
- Сервер имеет публичный IP-адрес и доступ в интернет.
- Доступен вход по SSH под `root` с паролем, выданным провайдером.
- На локальном компьютере доступны `ssh` и `ssh-keygen`.

В командах замените `<VPS_IP>` на публичный IP-адрес сервера, без угловых скобок. Блоки **Локально** выполняются в терминале вашего компьютера, блоки **На VPS** — в SSH-сессии под `root`. Команды на VPS не требуют `sudo`.

## 1. Подключение к VPS

**Локально:**

```bash
ssh root@<VPS_IP>
```

При первом подключении сверьте отпечаток ключа сервера с данными провайдера, подтвердите подключение и введите пароль `root`.

**На VPS:**

```bash
whoami
cat /etc/os-release
```

Ожидается пользователь `root`, а в сведениях об ОС — `ID=ubuntu`, `VERSION_ID="24.04"` и `VERSION_CODENAME=noble`. Если версия отличается, остановитесь: эта инструкция рассчитана на Ubuntu 24.04 LTS.

## 2. Подготовка операционной системы

**На VPS:**

```bash
apt update
apt upgrade -y
apt install -y ca-certificates curl git
```

Дождитесь успешного завершения каждой команды. При ошибке не переходите к следующему шагу. Если система предлагает диалог о локально изменённой конфигурации SSH, сохраните текущую конфигурацию.

Проверьте необходимость перезагрузки:

```bash
if [ -f /var/run/reboot-required ]; then
  cat /var/run/reboot-required
else
  echo 'Перезагрузка не требуется'
fi
```

Если требуется перезагрузка, выполните **на VPS**:

```bash
reboot
```

SSH-сессия завершится. Дождитесь запуска сервера и подключитесь повторно **локально**:

```bash
ssh root@<VPS_IP>
```

## 3. Установка Docker Engine и Docker Compose

Порядок установки соответствует [официальной документации Docker для Ubuntu](https://docs.docker.com/engine/install/ubuntu/). Используется официальный APT-репозиторий и Compose plugin.

**На VPS:** добавьте GPG-ключ Docker:

```bash
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
```

Создайте `/etc/apt/sources.list.d/docker.sources` в формате deb822:

```bash
tee /etc/apt/sources.list.d/docker.sources > /dev/null <<EOF_DOCKER
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF_DOCKER

apt update
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
```

Для Ubuntu 24.04 значение `Suites` будет `noble`; архитектура определяется автоматически.

## 4. Запуск и проверка Docker

**На VPS:**

```bash
systemctl enable --now docker
systemctl status docker --no-pager
docker --version
docker compose version
docker run --rm hello-world
```

Служба должна иметь состояние `active (running)`. Команды версий должны завершиться успешно. Тестовый контейнер должен вывести `Hello from Docker!` и завершиться; флаг `--rm` удалит его после завершения.

Если проверка не проходит, изучите журнал **на VPS** и устраните причину перед продолжением:

```bash
journalctl -u docker -n 100 --no-pager
```

## 5. Настройка SSH-доступа по ключу

### 5.1. Генерация ключа

**Локально:**

```bash
ssh-keygen -t ed25519 -f ~/.ssh/deployment_playbook_ed25519 -C "deployment-playbook"
```

Задайте парольную фразу для приватного ключа. Если файл с таким именем уже существует, не перезаписывайте его: используйте существующий ключ либо выберите другое имя и замените путь во всех командах ниже.

Создаются два файла:

- `~/.ssh/deployment_playbook_ed25519` — приватный ключ, остаётся на локальном компьютере.
- `~/.ssh/deployment_playbook_ed25519.pub` — публичный ключ, добавляется на VPS.

### 5.2. Добавление публичного ключа

Выберите один из двух способов. Оба добавляют ключ, сохраняя существующее содержимое `/root/.ssh/authorized_keys`.

**Локально, если доступен `ssh-copy-id`:**

```bash
ssh-copy-id -i ~/.ssh/deployment_playbook_ed25519.pub root@<VPS_IP>
```

Введите текущий пароль `root` на VPS.

**Локально на macOS, ручной вариант без `ssh-copy-id`:**

```bash
cat ~/.ssh/deployment_playbook_ed25519.pub | ssh root@<VPS_IP> 'umask 077; mkdir -p /root/.ssh; printf "\n" >> /root/.ssh/authorized_keys; cat >> /root/.ssh/authorized_keys; chmod 700 /root/.ssh; chmod 600 /root/.ssh/authorized_keys'
```

Команда передаёт только публичный ключ через SSH и дописывает его в `authorized_keys`.

### 5.3. Права доступа

В существующей SSH-сессии **на VPS** проверьте владельца и установите права:

```bash
chown root:root /root/.ssh /root/.ssh/authorized_keys
chmod 700 /root/.ssh
chmod 600 /root/.ssh/authorized_keys
ls -ld /root/.ssh
ls -l /root/.ssh/authorized_keys
```

Ожидаются владелец и группа `root`, права `drwx------` для `.ssh` и `-rw-------` для `authorized_keys`.

### 5.4. Проверка подключения

Оставьте текущую SSH-сессию открытой. В новом терминале **локально** выполните:

```bash
ssh -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -i ~/.ssh/deployment_playbook_ed25519 root@<VPS_IP> 'whoami'
```

Ожидается вывод `root` и успешное завершение команды. Допустим запрос парольной фразы локального приватного ключа; пароль учётной записи VPS для этой проверки не используется. При отказе проверьте выбранный ключ, содержимое `authorized_keys` и права через сохранённую SSH-сессию.

Парольную авторизацию и вход под `root` не отключаем. Конфигурацию SSH-сервера на этом этапе не изменяем.

## 6. Подготовка директории приложений

Инфраструктурные репозитории размещаются в `/opt`. Для будущего приложения используется каталог `/opt/application-infra`.

**На VPS:**

```bash
install -m 0755 -d /opt
ls -ld /opt
```

Каталог `/opt` должен существовать и принадлежать `root`. Репозиторий инфраструктуры будет клонирован в `/opt/application-infra` на следующем этапе; сейчас эту директорию не создаём, чтобы путь оставался свободным для клонирования.

На VPS размещаются конфигурации инфраструктуры и Docker-образы. Исходный код Java-приложения на VPS не клонируется. Сборка образов будет выполняться в CI, запуск — через Docker Compose.

## 7. Проверка готовности

**На VPS:**

```bash
systemctl is-enabled docker
systemctl is-active docker
docker version
docker compose version
git --version
ls -ld /opt
```

Ожидаемые результаты:

| Проверка | Ожидаемый результат |
| --- | --- |
| Автозапуск Docker | `enabled` |
| Состояние Docker | `active` |
| `docker version` | Выведены секции `Client` и `Server`, ошибок подключения нет |
| `docker compose version` | Выведена версия Docker Compose |
| `git --version` | Выведена версия Git |
| `/opt` | Каталог существует, владелец `root` |
| `hello-world` из раздела 4 | Выведено `Hello from Docker!`, контейнер успешно завершился |

**Локально:** повторите проверку SSH с явным выбором ключа:

```bash
ssh -o IdentitiesOnly=yes -o PreferredAuthentications=publickey -i ~/.ssh/deployment_playbook_ed25519 root@<VPS_IP> 'whoami'
```

Ожидается `root`. Если все проверки успешны, VPS готов к размещению инфраструктурного репозитория и последующему развёртыванию приложения.

Следующий раздел: [Подготовка инфраструктурного репозитория](03-infra-repository.md).
