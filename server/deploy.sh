#!/usr/bin/env bash
# Развёртывание бэкенда ЛК Интерра одной командой.
# Требуется: docker + docker compose, и файл serviceAccountKey.json рядом.
set -euo pipefail
cd "$(dirname "$0")"

if [ ! -f serviceAccountKey.json ]; then
  echo "ОШИБКА: положите serviceAccountKey.json в папку server/ (ключ Firebase Admin SDK)."
  exit 1
fi

if [ ! -f .env ]; then
  TOKEN="$(openssl rand -hex 24)"
  echo "ADMIN_TOKEN=$TOKEN" > .env
  echo "Создан .env. ADMIN_TOKEN=$TOKEN"
  echo "  ^ это пароль для входа в админку — сохраните его."
fi

echo "Сборка и запуск контейнера..."
docker compose up -d --build

echo "Жду старт..."
for i in $(seq 1 15); do
  if curl -fsS http://localhost:8080/health >/dev/null 2>&1; then
    echo "Бэкенд запущен: http://localhost:8080/health -> OK"
    echo "Админка: http://<адрес-сервера>:8080/admin.html"
    echo "(за nginx с HTTPS — https://push.interra.ru/admin.html)"
    exit 0
  fi
  sleep 1
done

echo "Не дождался /health. Логи: docker compose logs -f"
exit 1
