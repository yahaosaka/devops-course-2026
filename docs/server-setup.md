# Конфигурация виртуальной машины devops-vm

Документ описывает итоговое состояние сервера после ПР № 5–7 и порядок его восстановления
со снимка `01-clean-install`. Команды с пометкой **[VM]** выполняются на сервере,
**[Хост]** — на хостовой системе (Windows: PowerShell для ssh/scp, WSL для rsync).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Средство виртуализации | Oracle VirtualBox 7.2 |
| Имя ВМ | devops-vm |
| ОС | Ubuntu Server 24.04 LTS (64-bit), установка без minimized и snaps |
| Оперативная память | 2048 МБ |
| Процессор | 2 ядра |
| Диск | 25 ГБ, VDI, динамически расширяемый; разметка «Use an entire disk» (LVM) |
| Имя узла | devops-vm, FQDN `devops-vm.devops.local` |

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Тип | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|---|
| Адаптер 1 | NAT | enp0s3 | 10.0.2.15/24 (DHCP) | выход в Интернет, apt; SSH с хоста через проброс порта |
| Адаптер 2 | Host-only (`VirtualBox Host-Only Ethernet Adapter`, 192.168.56.0/24) | enp0s8 | 192.168.56.101/24 (DHCP) | прямой доступ с хоста: HTTP/HTTPS, имя devops.local |

Оба адаптера настраиваются до первого запуска машины.

## 3. Правило проброса портов

Адаптер 1 (NAT) → «Проброс портов»:

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | — | **2222** (до задания 2 ПР № 5 было 22) |

## 4. Учётные записи

| Имя | Группы | Аутентификация |
|---|---|---|
| student | student, adm, cdrom, sudo, dip, plugdev, lxd | создана установщиком; вход по SSH запрещён (`AllowUsers devops`), только локальная консоль |
| devops | devops, sudo, docker | SSH только по ключу ed25519 `~/.ssh/devops_vm` (комментарий `devops-vm-key`); пароль используется только для sudo |

Восстановление:

```bash
# [VM] (консоль или ssh student@127.0.0.1 -p 2222, пока порт гостя = 22)
sudo adduser devops                 # пароль для sudo
sudo usermod -aG sudo devops

# [Хост] ключ уже существует в ~/.ssh/devops_vm; размещение открытого ключа:
#   Linux/WSL/Git Bash:
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
#   PowerShell:
type $env:USERPROFILE\.ssh\devops_vm.pub | ssh devops@127.0.0.1 -p 2222 "mkdir -p ~/.ssh && chmod 700 ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys"
```

Права: `~/.ssh` — 700, `~/.ssh/authorized_keys` — 600.

`~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

* Основной файл `/etc/ssh/sshd_config` не изменяется; эталонная копия — `/etc/ssh/sshd_config.backup`.
* Изменения — в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30
AllowUsers devops
X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

* В `/etc/ssh/sshd_config.d/50-cloud-init.conf` (если есть) строка `PasswordAuthentication yes`
  закомментирована — иначе она действует раньше файла 99-.
* Активация по сокету отключена, иначе порт берётся из `ssh.socket` (22).

Порядок применения (действующую сессию не закрывать, проверять в новом терминале):

```bash
# [VM]
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo nano /etc/ssh/sshd_config.d/99-hardening.conf          # содержимое выше
grep -r "PasswordAuthentication" /etc/ssh/sshd_config.d/ /etc/ssh/sshd_config
sudo sed -i 's/^PasswordAuthentication yes/#&/' /etc/ssh/sshd_config.d/50-cloud-init.conf 2>/dev/null
sudo sshd -t && echo "Конфигурация корректна"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd                                    # 0.0.0.0:2222
# VirtualBox: проброс ssh — порт гостя 22 -> 2222
# [Хост] новый терминал
ssh devops
```

Проверка: `sudo sshd -T | grep -Ei '^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)'`.

## 6. Правила межсетевого экрана

Политики: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`; журналирование `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp | LIMIT IN | SSH rate-limited |
| 80/tcp | ALLOW IN | HTTP |
| 443/tcp | ALLOW IN | HTTPS |

(для каждого правила ufw создаёт парное правило `(v6)`).

```bash
# [VM] разрешающие правила — ДО ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
sudo ufw status verbose
```

`ufw allow ssh` не использовать: имя `ssh` раскрывается по `/etc/services` в порт 22.

### Разрешение имён

* Хост (`C:\Windows\System32\drivers\etc\hosts` либо `/etc/hosts`, правка от администратора):
  `192.168.56.101    devops.local`; в Windows затем `ipconfig /flushdns`.
* Сервер:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f                        # devops-vm.devops.local
```

## 7. Снимки состояния

| Снимок | Момент создания |
|---|---|
| 01-clean-install | после установки ОС, `apt upgrade`, перед аудиторной частью ПР № 5 (ВМ выключена) |
| 02-keys-configured | ПР № 5, после настройки ключевой аутентификации и `~/.ssh/config` |
| 03-ssh-hardened | ПР № 5, после усиления SSH (порт 2222, пароли отключены) |
| 04-nginx-https | ПР № 6, после перевода ресурса на HTTPS |
| 05-docker-compose | ПР № 7, после запуска «приложение + СУБД» |

## 8. Веб-сервер

* Пакет: `nginx` из репозитория Ubuntu (`sudo apt install -y nginx`), версия 1.24.x.
* Конфигурация ресурса: `/etc/nginx/sites-available/devops-site`, активирована ссылкой
  `/etc/nginx/sites-enabled/devops-site`; ссылка `sites-enabled/default` удалена
  (файл `sites-available/default` сохранён). Полный текст — `config/devops-site` в репозитории.
* Каталог ресурса: `/var/www/devops-site`, владелец `devops:devops`, каталоги 755, файлы 644;
  содержимое — каталог `site/` репозитория, доставка `scripts/deploy.sh`.
* Сертификат: `/etc/ssl/certs/devops.crt` — 644, root; ключ: `/etc/ssl/private/devops.key` — 600, root.
  Самоподписанный RSA 2048, срок 365 дней, CN и SAN `DNS:devops.local`.
* Журналы: `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log`.
* Порты 80 (перенаправление 301 на HTTPS) и 443 (TLSv1.2, TLSv1.3); HSTS не используется.

```bash
# [VM]
sudo apt update && sudo apt install -y nginx rsync
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /etc/ssl/private/devops.key \
  -out /etc/ssl/certs/devops.crt \
  -subj "/CN=devops.local" \
  -addext "subjectAltName=DNS:devops.local"
sudo chmod 600 /etc/ssl/private/devops.key
sudo nano /etc/nginx/sites-available/devops-site      # текст из config/devops-site
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx

# [Хост]
scp devops:/etc/ssl/certs/devops.crt ~/devops.crt
scripts/deploy.sh
curl --cacert ~/devops.crt -I https://devops.local
```

## 9. Контейнеризация

* Docker Engine установлен из официального репозитория `download.docker.com` (не пакет `docker.io`),
  пакеты `docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin`;
  версия Engine — см. `docker version --format '{{.Server.Version}}'` (требуется ≥ 28.0).
* Группа `docker`: только `devops` (у неё есть sudo; участник группы docker фактически root).
* Проект: `/home/devops/app` (`~/app`), доставляется из каталога `app/` репозитория:
  `rsync -avz --delete --exclude=.env app/ devops:app/`. Имя проекта Compose — `app`.
* Секреты: `/home/devops/app/.env`, права 600, владелец devops, создаётся только на сервере
  из `.env.example`, пароль `openssl rand -hex 16`; в Git и в образ не попадает
  (`.gitignore`, `.dockerignore`).
* Сервисы: `db` — `postgres:16-alpine`, порт не публикуется; `app` — образ `devops-app:1.0`
  (python:3.12-slim, пользователь `app`, gunicorn на 0.0.0.0:5000 внутри контейнера),
  публикация `127.0.0.1:5000:5000`. Оба — `restart: unless-stopped`; app стартует после
  `service_healthy` у db.
* Сеть: пользовательская bridge-сеть `app_backend`; приложение обращается к СУБД по имени `db`.
* Том: `app_db_data` → `/var/lib/postgresql/data`.
* Обратный прокси: `location /app/` в HTTPS-блоке `devops-site` → `http://127.0.0.1:5000/`
  с заголовками Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto.

```bash
# [VM] установка Docker Engine (docs.docker.com/engine/install/ubuntu)
for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do sudo apt-get remove -y $pkg; done
sudo apt-get update && sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo usermod -aG docker devops          # затем новая SSH-сессия
docker run --rm hello-world

# [Хост]
rsync -avz --delete --exclude=.env app/ devops:app/

# [VM]
cd ~/app
cp .env.example .env && chmod 600 .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 16)/" .env
docker compose up -d --build
docker compose ps                                   # db (healthy)
# добавить location /app/ в devops-site (раздел 8), затем:
sudo nginx -t && sudo systemctl reload nginx
```

Проверка всей конфигурации: `scripts/audit.sh; echo $?` → 0.
