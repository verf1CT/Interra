# RuStore Push — план внедрения (для устройств без Google-сервисов)

Зачем: текущие push идут через **FCM**, а он работает только там, где есть
сервисы Google Play. На **Huawei** и части российских прошивок их нет — туда
уведомления не доходят. RuStore Push закрывает этот сегмент.

> Статус: **не внедрено**. Это отдельная нативная интеграция + отправка через
> RuStore Push API. Требует доступа в RuStore Console (Project ID, сервисный
> ключ отправки) и сборки/проверки на реальном устройстве без Google-сервисов.
> Ниже — полный план. Точные версии SDK и URL API сверяйте с актуальной
> документацией RuStore (<https://www.rustore.ru/help/sdk/push-notifications>) —
> они меняются, здесь намеренно не захардкожены.

---

## Архитектура

Двухпровайдерная схема, FCM остаётся как есть:

```
Устройство с Google → FCM-токен  ─┐
                                   ├─→ бэкенд (по provider) → FCM Push API
Устройство без Google → RuStore-токен ┘                    → RuStore Push API
```

- Приложение получает токен **того провайдера, который доступен** на устройстве
  (FCM или RuStore), и регистрирует его на бэкенде с пометкой `provider`.
- Бэкенд при рассылке делит токены по `provider` и шлёт каждый своим API.

---

## 1. RuStore Console (доступы — на админах)

1. Завести/выбрать проект приложения `ru.interra.lk_interra`.
2. Включить **Push-уведомления**, получить **Project ID**.
3. Выпустить **сервисный ключ** для серверной отправки (service token / ключ
   доступа к Push API). Передать на бэкенд как секрет (`RUSTORE_SERVICE_TOKEN`),
   по аналогии с `serviceAccountKey.json` для FCM.

## 2. Приложение (Android, нативно)

- Подключить maven-репозиторий RuStore и зависимость push-SDK в
  `android/settings.gradle.kts` / `android/app/build.gradle.kts`.
- Инициализировать SDK с Project ID (в `Application`/`MainActivity`).
- Получить RuStore push-токен и отправить на бэкенд через `ApiClient` с
  `provider: 'rustore'` (см. правку регистрации ниже).
- Реализовать сервис приёма сообщений RuStore → показывать уведомление в том же
  канале `interra_default` (переиспользовать логику `PushService`).
- **FCM не трогаем** — оставляем для устройств с Google. На устройстве, где нет
  Google-сервисов, `getToken()` FCM не сработает, зато отработает RuStore.

> Важно: не ломать текущую CI-сборку AAB. Все правки Gradle — аддитивные,
> проверять `flutter build appbundle --release` (или зелёный CI) после каждой.

## 3. Бэкенд (сервер)

Минимальные аддитивные изменения (FCM-путь не затрагивается):

- **Регистрация**: принять и хранить необязательное поле `provider`
  (`fcm` по умолчанию | `rustore`). Миграция: `ALTER TABLE devices ADD COLUMN
  provider TEXT NOT NULL DEFAULT 'fcm'` (по образцу миграции `opens` в `db.js`).
- **`selectTokens`**: возвращать токены с их `provider` (или две группы).
- **Новый сендер** `src/rustore.js`: отправка на RuStore Push API с
  `RUSTORE_SERVICE_TOKEN`, с чисткой «мёртвых» токенов — как `fcm.js`.
- **`runBroadcast`** (`src/broadcast.js`): слать FCM-токены через `sendToTokens`,
  а RuStore-токены — через новый сендер; счётчики суммировать.
- Панель менять не нужно — метрики те же (recipients/success/opens).

## 4. Проверка

- Тестовое устройство **без сервисов Google** (Huawei или эмулятор RuStore).
- Регистрация → в БД строка с `provider='rustore'`.
- Рассылка из панели → уведомление приходит на RuStore-устройство.
- Убедиться, что на обычном Android (с Google) ничего не сломалось — FCM как был.

---

## Оценка

- Backend-groundwork (`provider`, разделение, сендер): ~полдня, тестируется локально.
- Android-нативка (SDK, токен, приём): ~1–2 дня, нужен доступ в RuStore Console
  и устройство для проверки.
- Основной блокер — **доступы RuStore Console** (Project ID + сервисный ключ).

См. также `docs/STORE_CHECKLIST.md` (раздел RuStore).
