#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                     # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

err() { echo "deploy: $*" >&2; }

# 1. Разбор аргумента --dry-run
DRY_RUN=()
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=(--dry-run) ;;
    *)         err "неизвестный аргумент: $1"; echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

# Требование 2: работа из любого каталога репозитория
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { err "запуск вне репозитория Git"; exit 1; }
cd "$REPO_ROOT"
LOCAL_DIR="${REPO_ROOT}/site/"

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    err "нет файла site/index.html — доставка отменена (иначе --delete удалит главную страницу)"
    exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet \
   || [[ -n "$(git ls-files --others --exclude-standard -- site/)" ]]; then
    err "в репозитории есть незафиксированные изменения — выполните commit перед деплоем:"
    git status --short >&2
    exit 1
fi

COMMIT="$(git rev-parse --short HEAD)"

# 3. Синхронизация: одно SSH-соединение, без интерактивного запроса пароля (требования 8, 9)
if ! rsync -az --delete --chmod=D755,F644 --itemize-changes ${DRY_RUN[@]+"${DRY_RUN[@]}"} \
        -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
        "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/"; then
    err "ошибка rsync (ключ, доступность сервера или права на ${REMOTE_DIR})"
    exit 1
fi

# 4. Пробный запуск — без проверки доступности
if [[ ${#DRY_RUN[@]} -gt 0 ]]; then
    echo "dry-run: план для коммита ${COMMIT} выведен, сервер не изменён"
    exit 0
fi

# 5. Проверка доступности с проверкой сертификата (без -k)
if ! curl -fsS --max-time 10 --cacert "$CA_CERT" -o /dev/null "${SITE_URL}/"; then
    err "файлы доставлены, но ${SITE_URL}/ недоступен"
    exit 1
fi

echo "Деплой выполнен: коммит ${COMMIT}, ${SITE_URL}/ отвечает 200"
exit 0
