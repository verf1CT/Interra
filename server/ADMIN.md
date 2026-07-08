# Сервер уведомлений ЛК Интерра — пошаговый запуск для администратора

Инструкция «делай по шагам сверху вниз — и push работает». Рассчитана на чистый
сервер **Ubuntu 22.04 / Debian 12**. Команды копируются как есть; где нужно
подставить своё — помечено `<...>`.

Про устройство кода см. [`README.md`](./README.md). Здесь — только эксплуатация.

---

## Оглавление

- [Шаг 0. Что понадобится (5 минут на подготовку)](#шаг-0-что-понадобится)
- [Шаг 1. Ключ Firebase (`serviceAccountKey.json`)](#шаг-1-ключ-firebase)
- [Шаг 2. DNS — направить домен на сервер](#шаг-2-dns)
- [Шаг 3. Подключиться к серверу и поставить пакеты](#шаг-3-пакеты)
- [Шаг 4. Скопировать проект на сервер](#шаг-4-код)
- [Шаг 5А. Запуск через Docker (рекомендуется)](#шаг-5а-docker)
- [Шаг 5Б. Запуск через systemd (без Docker)](#шаг-5б-systemd)
- [Шаг 6. HTTPS: nginx + сертификат](#шаг-6-https)
- [Шаг 7. Проверка, что всё живо](#шаг-7-проверка)
- [Шаг 8. Первая тестовая рассылка](#шаг-8-первая-рассылка)
- [Дальше: работа с панелью](#работа-с-панелью)
- [Справка по API](#справка-api)
- [Обслуживание](#обслуживание)
- [Если что-то не работает](#диагностика)
- [Безопасность](#безопасность)

---

<a id="шаг-0-что-понадобится"></a>
## Шаг 0. Что понадобится

Проверьте по списку — без этого дальше идти нельзя:

- [ ] **Сервер** (VPS) с Ubuntu/Debian и доступом по SSH под `root` или `sudo`.
- [ ] **Домен** `push.interra.ru` (или свой) — им уже пользуется приложение
      (`app/lib/config.dart` → `backendBaseUrl = 'https://push.interra.ru'`).
      Если домен другой — его надо поменять и в приложении, и пересобрать APK.
- [ ] Доступ в **Firebase Console** проекта, к которому подключено приложение.
- [ ] Открытые порты **80** и **443** на сервере (для HTTP/HTTPS).

> Если домена/HTTPS пока нет — можно поднять сервер и слать push скриптом (Шаг 8,
> вариант «топик»), но приложение регистрировать устройства не сможет, пока не
> будет `https://push.interra.ru`.

---

<a id="шаг-1-ключ-firebase"></a>
## Шаг 1. Ключ Firebase (`serviceAccountKey.json`)

Без этого файла реальные push не уходят (сервер работает в «холостом» режиме).

1. Откройте <https://console.firebase.google.com/> → нужный проект.
2. Шестерёнка вверху слева → **Project settings**.
3. Вкладка **Service accounts**.
4. Кнопка **Generate new private key** → **Generate key**.
5. Скачается JSON-файл — переименуйте в **`serviceAccountKey.json`**.

Держите файл под рукой — на Шаге 4 он ляжет в `server/`.

> ⚠️ Это секрет: полный доступ к отправке push проекта. Не коммитить в git
> (уже в `.gitignore`), не пересылать в мессенджерах.

---

<a id="шаг-2-dns"></a>
## Шаг 2. DNS

В панели вашего DNS-провайдера создайте **A-запись**:

```
push.interra.ru.   A   <IP-адрес-вашего-сервера>
```

Проверьте, что запись разошлась (с любого компьютера):

```bash
dig +short push.interra.ru      # должен вернуть IP сервера
# или: nslookup push.interra.ru
```

Пока `dig` не показывает нужный IP — сертификат на Шаге 6 не выпустится. DNS
может обновляться до нескольких часов.

---

<a id="шаг-3-пакеты"></a>
## Шаг 3. Пакеты на сервере

Подключитесь по SSH и поставьте всё нужное.

```bash
ssh root@<IP-адрес-сервера>

# обновить систему
apt update && apt upgrade -y

# базовые утилиты
apt install -y git curl ufw

# firewall: пускаем SSH, HTTP, HTTPS
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
```

Дальше — **выберите один способ запуска**: Docker (Шаг 5А, проще) **или**
systemd (Шаг 5Б). Ставьте пакеты только для выбранного.

**Для Docker (Шаг 5А):**

```bash
curl -fsSL https://get.docker.com | sh
docker --version && docker compose version   # проверка
```

**Для systemd (Шаг 5Б):** Node.js 18–20:

```bash
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt install -y nodejs
node --version   # v20.x
```

---

<a id="шаг-4-код"></a>
## Шаг 4. Код на сервер

```bash
mkdir -p /opt/interra
cd /opt/interra
git clone https://github.com/verf1CT/Interra.git .
# в результате должна появиться папка /opt/interra/server
cd /opt/interra/server
```

Загрузите сюда ключ Firebase со Шага 1. С вашего локального компьютера:

```bash
scp serviceAccountKey.json root@<IP-адрес-сервера>:/opt/interra/server/
```

Проверьте на сервере и закройте права:

```bash
cd /opt/interra/server
ls -l serviceAccountKey.json     # файл на месте
chmod 600 serviceAccountKey.json # доступ только владельцу
```

---

<a id="шаг-5а-docker"></a>
## Шаг 5А. Запуск через Docker (рекомендуется)

Один скрипт делает всё: создаёт `.env` со случайным паролём, собирает и
поднимает контейнер, ждёт готовности.

```bash
cd /opt/interra/server
./deploy.sh
```

Скрипт выведет строку вида:

```
Создан .env. ADMIN_TOKEN=3f9c1a...   ← ЭТО ПАРОЛЬ ОТ АДМИНКИ, СОХРАНИТЕ ЕГО
```

**Скопируйте `ADMIN_TOKEN` в надёжное место** — им операторы входят в панель.
Позже его всегда можно посмотреть: `cat /opt/interra/server/.env`.

Проверка, что контейнер поднялся:

```bash
docker compose ps                 # STATUS = Up
curl -s http://localhost:8080/health   # {"ok":true}
```

Полезные команды на будущее:

```bash
docker compose logs -f            # смотреть логи
docker compose restart            # перезапустить
docker compose up -d --build      # пересобрать после git pull
docker compose down               # остановить (база в томе сохранится)
```

БД хранится в docker-томе `interra-data` и переживает пересборку.

➡️ Переходите к **Шагу 6 (HTTPS)**.

---

<a id="шаг-5б-systemd"></a>
## Шаг 5Б. Запуск через systemd (без Docker)

Если не хотите Docker — сервис под управлением systemd (автозапуск, рестарт при
падении). В репозитории уже лежит готовый unit `deploy/interra-backend.service`
(рассчитан на пользователя `interra` и путь `/opt/interra/server`).

```bash
cd /opt/interra/server

# 1) отдельный системный пользователь (без входа в систему)
useradd --system --home /opt/interra --shell /usr/sbin/nologin interra || true

# 2) зависимости
npm ci

# 3) .env с паролём админки и явными путями (не зависят от рабочей директории)
cat > .env <<EOF
ADMIN_TOKEN=$(openssl rand -hex 24)
DB_PATH=/opt/interra/server/data/interra.sqlite
FIREBASE_SERVICE_ACCOUNT=/opt/interra/server/serviceAccountKey.json
EOF
cat .env        # ← сохраните ADMIN_TOKEN

# 4) права: пусть всё принадлежит пользователю interra
chown -R interra:interra /opt/interra/server

# 5) установить и запустить сервис
cp deploy/interra-backend.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now interra-backend
```

Проверка:

```bash
systemctl status interra-backend       # active (running)
curl -s http://localhost:8080/health    # {"ok":true}
journalctl -u interra-backend -f        # логи; ждём строку:
                                        # [fcm] Firebase инициализирован — push включён.
```

> Если в логе вместо этого `[fcm] Ключ Firebase не найден` — проверьте путь
> `FIREBASE_SERVICE_ACCOUNT` в `.env` и что файл на месте с правами `600`.

После обновления кода (`git pull`) перезапуск: `systemctl restart interra-backend`.

➡️ Переходите к **Шагу 6 (HTTPS)**.

---

<a id="шаг-6-https"></a>
## Шаг 6. HTTPS: nginx + сертификат

Приложение ходит только по HTTPS, поэтому ставим nginx перед сервером на :8080.

```bash
# 1) nginx и certbot
apt install -y nginx certbot python3-certbot-nginx

# 2) конфиг из репозитория (проксирует push.interra.ru -> 127.0.0.1:8080)
cp /opt/interra/server/deploy/nginx-push.interra.ru.conf \
   /etc/nginx/sites-available/push.interra.ru

# 3) включить сайт
ln -sf /etc/nginx/sites-available/push.interra.ru \
       /etc/nginx/sites-enabled/push.interra.ru
```

> Если ваш домен **не** `push.interra.ru`, отредактируйте `server_name` в
> `/etc/nginx/sites-available/push.interra.ru` перед следующим шагом.

Выпустить бесплатный сертификат Let's Encrypt (certbot сам пропишет пути в конфиг
и настроит автопродление):

```bash
certbot --nginx -d push.interra.ru
# ответьте на вопросы (email, согласие). Выберите редирект на HTTPS, если спросит.

nginx -t && systemctl reload nginx      # проверка конфига и перезагрузка
```

Готово: панель доступна по `https://push.interra.ru/admin.html`.

---

<a id="шаг-7-проверка"></a>
## Шаг 7. Проверка, что всё живо

Выполните по порядку — все три должны отвечать так, как указано:

```bash
# 1) сервер отвечает локально
curl -s http://localhost:8080/health
# → {"ok":true}

# 2) сервер доступен снаружи по HTTPS
curl -s https://push.interra.ru/health
# → {"ok":true}

# 3) API отвечает и FCM включён (подставьте свой ADMIN_TOKEN)
curl -s -H "Authorization: Bearer <ADMIN_TOKEN>" \
     https://push.interra.ru/api/admin/stats
# → в ответе "fcmEnabled":true  и статистика устройств
```

Если `fcmEnabled` = `false` — ключ Firebase не подхватился (см. §Диагностика).

Откройте в браузере `https://push.interra.ru/admin.html`, введите `ADMIN_TOKEN` —
должна появиться панель с блоком «Состояние» и зелёной плашкой FCM.

---

<a id="шаг-8-первая-рассылка"></a>
## Шаг 8. Первая тестовая рассылка

**Вариант А — через панель:** «Кому» = *Всем клиентам*, заголовок и текст →
**Отправить**. Внизу в «Последних рассылках» появится запись с числом доставок.

**Вариант Б — через API** (проверка «на всех Android» топиком `all`, минуя базу —
работает, даже если ещё нет ни одного зарегистрированного устройства):

```bash
cd /opt/interra/server
node scripts/send-test-push.js --topic all "Интерра" "Проверка связи"
# → ✅ Отправлено, messageId: ...
```

Если push пришёл на телефон с установленным приложением — **сервер полностью
готов**. 🎉

---

<a id="работа-с-панелью"></a>
## Работа с панелью (для операторов)

Адрес: `https://push.interra.ru/admin.html`. Вход по `ADMIN_TOKEN` (сохраняется в
браузере, повторно вводить не нужно).

Блоки:
- **Состояние** — включён ли FCM, число устройств, разбивка по платформам.
- **Новое уведомление** — «Кому», «Заголовок», «Текст» → **Отправить**.
- **Последние рассылки** — журнал: цель, доставлено / ошибок, время.

### «Кому» — три способа адресации

| В панели | Кому придёт | Что вводить в «значение» |
|----------|-------------|--------------------------|
| **Всем клиентам** | Всем зарегистрированным устройствам | — |
| **По сегменту** | Только подписанным на категорию | ключ сегмента (см. ниже) |
| **Конкретному логину** | Устройствам этого абонента | логин = номер телефона |

**Ключи сегментов** (категории уведомлений в приложении):

| Ключ | Категория в приложении |
|------|------------------------|
| `outage` | Аварии и работы |
| `balance` | Баланс и оплата |
| `news` | Новости и акции |

> Перед массовой рассылкой отправьте на свой `login` — проверить текст.

---

<a id="справка-api"></a>
## Справка по API

Админ-запросы требуют заголовок `Authorization: Bearer <ADMIN_TOKEN>`.

**Статистика:**

```bash
curl -H "Authorization: Bearer <ADMIN_TOKEN>" \
     https://push.interra.ru/api/admin/stats
```

**Рассылка:**

```bash
curl -X POST https://push.interra.ru/api/admin/broadcast \
  -H "Authorization: Bearer <ADMIN_TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Акция октября",
    "body": "Скидка 20% на тариф до конца месяца",
    "target": { "type": "segment", "value": "news" },
    "imageUrl": "https://interra.ru/promo/banner.jpg",
    "link": "https://interra.ru/promo"
  }'
```

- `target.type`: `all` | `segment` | `login`; для `segment`/`login` обязателен
  `target.value`.
- `imageUrl` (необязательно, только `https`) — **картинка в уведомлении**
  (rich push). На Android рисуется системным треем сама; на iOS нужен
  Notification Service Extension — исходники готовы, подключение описано в
  `docs/IOS_PUSH_SETUP.md` (без него iOS-пуш придёт без картинки).
- `link` (необязательно, только `https`) — **открывается по тапу** по уведомлению.
- `data` — произвольные пары для приложения.
- `sendAt` (необязательно, ISO-время в будущем) — **отложенная рассылка**:
  сервер не шлёт сразу, а поставит в очередь и отправит в указанное время
  (фоновый планировщик проверяет очередь каждые 30 c; интервал настраивается
  переменной `SCHEDULER_TICK_MS`). Ответ: `{ ok, scheduled: true, id, sendAt }`.
- Ответ немедленной рассылки: `{ ok, recipients, successCount, failureCount }`.
  Все рассылки видны в панели во вкладке «Аналитика рассылок».

Управление отложенными: `GET /api/admin/scheduled` — список ожидающих;
`POST /api/admin/scheduled/:id/cancel` — отмена. В панели это блок
«Запланированные рассылки» с кнопкой «Отменить».

> Предохранитель: перед отправкой на цель **«Всем клиентам»** панель показывает
> подтверждение с предпросмотром (заголовок, текст, число устройств).

**Эндпоинты приложения** (вызывает клиент, без токена):
`POST /api/devices/register` и `POST /api/devices/unregister`. Регистрация
ограничена: **30 запросов с IP в минуту** (иначе `429`). Плюс
`POST /api/events/opened` `{ bid }` — приложение отмечает открытие рассылки
(тап по пушу со ссылкой), из чего в панели считается **open-rate / CTR**.

**Скрипт прямой отправки** (в обход базы, нужен только ключ Firebase):

```bash
node scripts/send-test-push.js --token <FCM_TOKEN> "Заголовок" "Текст"  # на устройство
node scripts/send-test-push.js --topic all          "Заголовок" "Текст"  # на всех
```

---

<a id="обслуживание"></a>
## Обслуживание

**Где посмотреть пароль админки:** `cat /opt/interra/server/.env`

**Обновить код:**

```bash
cd /opt/interra/server && git pull
# Docker:   docker compose up -d --build
# systemd:  npm ci && systemctl restart interra-backend
```

**Сменить `ADMIN_TOKEN`:** отредактируйте `.env`, затем
`docker compose up -d` (Docker) или `systemctl restart interra-backend` (systemd).
Старый токен сразу перестаёт работать.

**Резервная копия базы** (токены + история рассылок — один файл SQLite):

```bash
# Docker
docker compose exec backend sh -c \
  "sqlite3 /data/interra.sqlite \".backup '/data/backup.sqlite'\"" 2>/dev/null || \
docker compose cp backend:/data/interra.sqlite ./interra-backup-$(date +%F).sqlite

# systemd (файл лежит в server/data/)
cp /opt/interra/server/data/interra.sqlite ./interra-backup-$(date +%F).sqlite
```

**Сертификат** продлевается автоматически (`certbot` ставит таймер). Проверка:
`certbot renew --dry-run`.

---

<a id="диагностика"></a>
## Если что-то не работает

| Симптом | Что делать |
|---------|-----------|
| `curl .../health` не отвечает | Сервер не поднялся: `docker compose logs -f` или `journalctl -u interra-backend -f` |
| В панели `503 ADMIN_TOKEN не настроен` | В `.env` пуст `ADMIN_TOKEN`, задайте и перезапустите |
| В панели `401 Неверный админ-токен` | Введён не тот токен, сверьте с `cat .env` |
| `"fcmEnabled": false` | Нет/не читается `serviceAccountKey.json`. Проверьте путь и права `600`, перезапустите |
| Рассылка «уходит», но push нет | Если FCM выключен — это dry-run (только лог). Включите ключ Firebase |
| `recipients: 0` | Нет устройств под целью: пустая база, неверный сегмент/логин |
| Устройства не регистрируются | Приложение не достаёт бэкенд: проверьте HTTPS/домен/firewall; или упёрлось в `429` |
| certbot: ошибка проверки домена | DNS ещё не указывает на сервер (`dig +short push.interra.ru`) или закрыт порт 80 |
| Ошибка `502 Bad Gateway` в nginx | Node-сервер не запущен на :8080 — см. первую строку таблицы |

Быстрый набор проверок:

```bash
curl -s http://localhost:8080/health
docker compose logs -f            # или: journalctl -u interra-backend -f
cat /opt/interra/server/.env      # посмотреть ADMIN_TOKEN
```

---

<a id="безопасность"></a>
## Безопасность — финальный чек-лист

- [ ] `ADMIN_TOKEN` — длинный, случайный, роздан только операторам.
- [ ] `serviceAccountKey.json` — права `600`, не в git, не в мессенджерах.
- [ ] Панель и API открыты только по HTTPS (nginx впереди).
- [ ] Порт `8080` наружу закрыт firewall'ом (`ufw`), доступен только через nginx.
- [ ] Настроен регулярный бэкап `interra.sqlite`.
- [ ] `certbot renew --dry-run` проходит без ошибок.
