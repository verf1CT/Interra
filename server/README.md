# Бэкенд ЛК Интерра

Node.js/Express сервер: регистрация устройств и рассылка push-уведомлений (FCM),
веб-панель оператора для отправки уведомлений всем / сегменту / конкретному клиенту.

## Запуск

```bash
cd server
npm install
cp .env.example .env      # на Windows: copy .env.example .env
# отредактируйте .env: задайте ADMIN_TOKEN
npm start
```

Сервер поднимется на `http://localhost:8080`.
Админ-панель: `http://localhost:8080/admin.html` (войти по `ADMIN_TOKEN`).

Без ключа Firebase сервер работает в режиме **dry-run**: регистрация устройств и
админка функционируют, а push не отправляется (сообщения логируются в консоль).
Это позволяет разрабатывать и тестировать до подключения Firebase.

## Подключение push (Firebase Cloud Messaging)

1. Создайте проект в [Firebase Console](https://console.firebase.google.com/).
2. Project settings → Service accounts → **Generate new private key**.
3. Сохраните файл как `server/serviceAccountKey.json` (он в `.gitignore`).
4. Убедитесь, что в `.env` указан путь `FIREBASE_SERVICE_ACCOUNT=./serviceAccountKey.json`.
5. Перезапустите сервер — в логе появится `[fcm] Firebase инициализирован — push включён.`

Тот же Firebase-проект подключается к мобильному приложению (`app/`):
`google-services.json` (Android) и `GoogleService-Info.plist` (iOS).

## API

### Для приложения

| Метод | Путь                       | Тело                                                            |
|-------|----------------------------|-----------------------------------------------------------------|
| POST  | `/api/devices/register`    | `{ token, clientLogin?, platform?, appVersion?, segments?, prefs? }` |
| POST  | `/api/devices/unregister`  | `{ token }`                                                      |

### Для оператора (заголовок `Authorization: Bearer <ADMIN_TOKEN>`)

| Метод | Путь                   | Описание                                                  |
|-------|------------------------|-----------------------------------------------------------|
| GET   | `/api/admin/stats`     | Статистика устройств и история рассылок                   |
| POST  | `/api/admin/broadcast` | Отправка: `{ title, body, target:{type,value?}, data? }` |

`target.type`: `all` (всем), `segment` (по тегу), `login` (конкретный логин UTM5).

## Дальнейшие шаги

- Автоматические уведомления о скором завершении тарифа и статусах заявок:
  фоновая задача опрашивает UTM5 и вызывает рассылку (см. план в корневом README).
