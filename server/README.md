# Сервер ЛК Интерра

Node.js (чистый JavaScript, ES modules) и Express. Хранит push-токены устройств, рассылает уведомления через Firebase Cloud Messaging, отдаёт веб-панель оператора и ведёт чат-бота поддержки для Telegram и MAX.

Если нужно просто поднять сервер на машине, идите в [`ADMIN.md`](./ADMIN.md): там пошаговая инструкция от чистого сервера до первой рассылки. Здесь устройство кода и справка по API.

## Как это работает

При запуске приложение регистрирует на сервере свой FCM-токен вместе с логином абонента и категориями уведомлений. Оператор через панель или API шлёт уведомление всем, по категории или одному логину. Сервер отдаёт его в FCM и сам чистит токены, которые Firebase признал мёртвыми. Рассылку можно запланировать: `scheduler.js` раз в 30 секунд смотрит, что пора отправить.

Без ключа Firebase сервер работает в режиме dry-run: регистрация и панель живут, а отправка идёт только в лог.

## Запуск

```bash
cp .env.example .env     # заполнить ADMIN_TOKEN и остальное
npm install
npm run dev              # node --watch
npm test                 # vitest, база в памяти
```

| Команда | Что делает |
|---------|-----------|
| `npm start` | обычный запуск |
| `npm run bot` | Telegram-бот отдельным процессом |
| `npm run bot:max` | бот для MAX |
| `npm run bot:sim` | диалог с ботом в консоли |
| `npm run build-ui` | собрать админку из `admin-ui/` в `public/` |
| `npm run test:coverage` | тесты с покрытием |

Переменные окружения (шаблон в `.env.example`):

| Переменная | Зачем |
|-----------|-------|
| `PORT` | порт, по умолчанию 8080 |
| `ADMIN_TOKEN` | токен для панели и админ-API, без него админ-запросы отклоняются |
| `FIREBASE_SERVICE_ACCOUNT` | путь к `serviceAccountKey.json` |
| `DB_PATH` | файл SQLite, по умолчанию `data/interra.sqlite` |
| `SCHEDULER_TICK_MS` | период опроса запланированных рассылок |
| `TELEGRAM_BOT_TOKEN`, `MAX_BOT_TOKEN`, `TELEGRAM_SALES_CHAT_ID` | боты и чат отдела продаж |
| `BILLING_API_URL`, `BILLING_API_TOKEN`, `CRM_API_URL`, `CRM_API_TOKEN`, `SBP_API_URL` | внешние системы бота; если не заданы, бот работает на встроенных заглушках |

`.env` и `serviceAccountKey.json` в git не попадают.

## Структура

| Путь | Назначение |
|------|-----------|
| `src/index.js` | сборка Express: статика панели, маршруты, обработка ошибок, `trust proxy`, фоновый планировщик |
| `src/config.js` | чтение окружения |
| `src/db.js` | SQLite через `better-sqlite3`, весь доступ к данным: `devices`, `broadcasts`, `scheduled_broadcasts` |
| `src/broadcast.js`, `src/fcm.js` | отправка через `firebase-admin`, мультикаст, чистка невалидных токенов |
| `src/scheduler.js` | отправка запланированных рассылок; запись помечается отправленной до отправки, чтобы пересекающиеся тики не продублировали её |
| `src/middleware/auth.js` | bearer-токен для админ-маршрутов, сравнение за постоянное время |
| `src/routes/` | `devices`, `admin`, `events`, `bot` |
| `src/bot/` | чат-бот: `botEngine.js` ведёт сценарий из `scenarioData.js`, клиенты Telegram и MAX, внешние системы за интерфейсами в `services/` |
| `admin-ui/` | исходники панели на React 19 и Vite, сборка пишется в `public/`, который сервер раздаёт как статику |
| `tests/` | Vitest: база, сервер, бот |
| `scripts/send-test-push.js` | тестовый пуш на один токен |
| `Dockerfile`, `docker-compose.yml`, `deploy.sh` | развёртывание, том `/data` для базы |

Состояние диалогов бота хранится в памяти (`Map`), после перезапуска сессии сбрасываются. Бота тестируют подменой сервисов через опции конструктора `BotEngine`.

## API

Для приложения, без админ-токена:

| Метод | Путь | Тело |
|-------|------|------|
| POST | `/api/devices/register` | `{ token, clientLogin?, platform?, appVersion?, segments?, prefs? }`, с ограничением частоты по IP |
| POST | `/api/devices/unregister` | `{ token }` |
| POST | `/api/events/opened` | `{ bid }` - отметка об открытии рассылки |

Для оператора, заголовок `Authorization: Bearer <ADMIN_TOKEN>`:

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/api/admin/stats` | статистика устройств, итоги и последние рассылки |
| GET | `/api/admin/devices` | список устройств |
| GET | `/api/admin/broadcasts` | журнал рассылок |
| POST | `/api/admin/broadcast` | отправка или планирование |
| GET | `/api/admin/scheduled` | ожидающие рассылки |
| POST | `/api/admin/scheduled/:id/cancel` | отмена запланированной |

Тело `broadcast`: `{ title, body, target: { type, value? }, data?, imageUrl?, link?, sendAt? }`. Цель: `all`, `segment` (категория) или `login` (логин UTM5). `imageUrl` и `link` должны быть https, `sendAt` - ISO-дата в будущем.

Бот и служебное:

| Метод | Путь | Описание |
|-------|------|----------|
| GET | `/health` | `{ ok: true }` |
| GET | `/api/bot/status` | состояние бота и сценария |
| POST | `/api/bot/webhook`, `/api/bot/max/webhook` | вебхуки Telegram и MAX |
| POST | `/api/bot/simulate` | прогон сценария без мессенджера |

Сценарий бота описан в [`../docs/CHATBOT_GUIDE.md`](../docs/CHATBOT_GUIDE.md).

## Прод

Адрес `push.interra.ru` за nginx, конфиг и юнит systemd лежат в [`../deploy/`](../deploy). Подробности - в [`ADMIN.md`](./ADMIN.md) и [`../docs/DEPLOY.md`](../docs/DEPLOY.md).
