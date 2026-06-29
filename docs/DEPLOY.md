# Развёртывание бэкенда на инфраструктуре Интерры

Рунбук для админов Интерры. Цель: поднять backend рассылки на
`https://push.interra.ru`, после чего приложение начнёт получать push.

Готовые файлы лежат в `deploy/`:
- `interra-backend.service` — systemd-юнит
- `nginx-push.interra.ru.conf` — обратный прокси с HTTPS

Адрес `push.interra.ru` уже прописан в приложении (`app/lib/config.dart`).
Если выберете другой поддомен — поправьте его там и пересоберите приложение.

---

## Самый простой путь — Docker одной командой

Если на сервере есть Docker:

```bash
git clone https://github.com/verf1CT/Interra.git /opt/interra
cd /opt/interra/server
# положить сюда ключ Firebase Admin SDK:
#   /opt/interra/server/serviceAccountKey.json
bash deploy.sh
```

`deploy.sh` сам создаст `.env` со случайным `ADMIN_TOKEN`, соберёт образ,
поднимет контейнер и проверит `/health`. БД хранится в docker-томе `interra-data`.

Останется только настроить DNS (шаг 1) и HTTPS-прокси (шаг 5).
Обновление: `cd /opt/interra && git pull && cd server && docker compose up -d --build`.

Ниже — полный путь без Docker (systemd + nginx), если Docker не используется.

---

## 1. DNS
Добавить A-запись: `push.interra.ru` → IP сервера, где будет крутиться backend.

## 2. Код и зависимости
```bash
sudo useradd -r -m -d /opt/interra interra      # сервисный пользователь (если нет)
sudo mkdir -p /opt/interra && cd /opt/interra
sudo git clone https://github.com/verf1CT/Interra.git .
cd server
sudo npm ci --omit=dev                            # нужен Node.js 18+
```

## 3. Секреты и конфигурация
Положить ключ Firebase Admin SDK (его НЕТ в git) и создать `.env`:
```bash
# /opt/interra/server/serviceAccountKey.json  — скопировать с защищённого места
sudo tee /opt/interra/server/.env >/dev/null <<'EOF'
PORT=8080
ADMIN_TOKEN=ПОСТАВЬТЕ_ДЛИННУЮ_СЛУЧАЙНУЮ_СТРОКУ
DB_PATH=/opt/interra/server/data/interra.sqlite
FIREBASE_SERVICE_ACCOUNT=/opt/interra/server/serviceAccountKey.json
EOF
sudo chown -R interra:interra /opt/interra
```

## 4. Автозапуск (systemd)
```bash
sudo cp /opt/interra/deploy/interra-backend.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now interra-backend
sudo systemctl status interra-backend         # должно быть active (running)
```
В логе ожидаем: `[fcm] Firebase инициализирован — push включён.`

## 5. HTTPS-прокси (nginx + certbot)
```bash
sudo cp /opt/interra/deploy/nginx-push.interra.ru.conf /etc/nginx/sites-available/push.interra.ru
sudo ln -s /etc/nginx/sites-available/push.interra.ru /etc/nginx/sites-enabled/
sudo certbot --nginx -d push.interra.ru        # выпустит сертификат и поправит конфиг
sudo nginx -t && sudo systemctl reload nginx
```

## 6. Проверка
```bash
curl https://push.interra.ru/health            # {"ok":true}
```
Админ-панель рассылки: `https://push.interra.ru/admin.html` (вход по `ADMIN_TOKEN`).

## 7. Обновления
```bash
cd /opt/interra && sudo git pull
cd server && sudo npm ci --omit=dev
sudo systemctl restart interra-backend
```

---

## Альтернатива: Docker
Если на сервере есть Docker — см. раздел «Деплой (Docker)» в `server/README.md`
(тот же `serviceAccountKey.json` подключается томом, БД в `/data`).
