# ЛК Интерра

[![CI](https://github.com/verf1CT/Interra/actions/workflows/ci.yml/badge.svg)](https://github.com/verf1CT/Interra/actions)

Личный кабинет абонентов интернет-провайдера [Интерра](https://interra.ru) (Первоуральск). Приложение для iOS и Android, плюс небольшой сервер для push-уведомлений и чат-бота поддержки.

В приложении можно посмотреть баланс и тариф, пополнить счёт, сходить в историю платежей и список услуг, глянуть тарифную сетку ТВ, проверить скорость и посмотреть, кто сидит в домашнем Wi-Fi. Есть светлая и тёмная темы, вход по Face ID, отпечатку или коду.

## Из чего состоит

| Папка | Что внутри |
|-------|-----------|
| `app/` | мобильное приложение на Flutter, основной продукт |
| `server/` | бэкенд на Node.js: push-рассылки, админка, чат-бот для Telegram и MAX |
| `deploy/` | конфиги nginx и systemd для боевого сервера |
| `docs/` | чеклисты публикации в магазины, настройка push, политика конфиденциальности |

## Как это работает

У данных три независимых пути.

1. **Приложение и биллинг.** Вход по телефону и SMS, баланс, платежи и услуги идут напрямую в кабинет UTM5 на `stat.interra.ru`. У UTM5 нет API, поэтому приложение скачивает страницы кабинета и разбирает HTML (`app/lib/services/cabinet_parser.dart`). Наш сервер в этом не участвует.
2. **Приложение и наш сервер.** Приложение один раз регистрирует push-токен устройства на `push.interra.ru`.
3. **Сервер и устройства.** Оператор запускает рассылку из веб-админки, из бота или по расписанию, сервер отправляет её через Firebase Cloud Messaging.

Если провайдер поменяет вёрстку кабинета, у абонентов пропадут баланс и тариф. Поэтому парсеры написаны как чистые функции и покрыты тестами на сохранённых страницах.

## Запуск приложения

Нужен Flutter 3.44 (версия зафиксирована в CI).

```bash
cd app
flutter pub get
flutter run
flutter analyze lib test
flutter test
```

Релизные сборки делает CI. Для `flutter build apk --release` локально нужен свой keystore.

Если путь к проекту содержит кириллицу, `flutter analyze` на Windows может упасть с `FormatException`. Помогает `subst I: "<путь к репозиторию>"` и запуск анализа из `I:\app`.

### Демо-режим

Для скриншотов магазинов и проверки модераторами в приложении есть демо-режим с вымышленным абонентом. В релизных сборках он по умолчанию выключен.

## Запуск сервера

Нужен Node.js 18 или новее.

```bash
cd server
cp .env.example .env     # заполнить ADMIN_TOKEN, ключи Firebase и ботов
npm install
npm run dev              # с автоперезапуском
npm test                 # тесты на Vitest, база в памяти
```

Остальные команды:

| Команда | Что делает |
|---------|-----------|
| `npm start` | обычный запуск |
| `npm run bot` | Telegram-бот отдельным процессом |
| `npm run bot:max` | бот для мессенджера MAX |
| `npm run bot:sim` | диалог с ботом в консоли |
| `npm run build-ui` | собрать админку из `admin-ui/` в `server/public` |

Без `ADMIN_TOKEN` админские запросы отклоняются. Файлы `.env` и `serviceAccountKey.json` в репозиторий не попадают.

Развёртывание описано в [`docs/DEPLOY.md`](docs/DEPLOY.md) и [`server/ADMIN.md`](server/ADMIN.md).

## CI и релизы

GitHub Actions прогоняет анализ и тесты Flutter, тесты сервера, собирает подписанные APK и AAB и IPA без подписи. После пуша в `main` публикуется релиз с тегом `build-<номер>`. IPA без подписи ставится через Sideloadly или AltStore. Из этих же артефактов приложение выкладывается в Google Play, RuStore и App Store.

## Документация

- [`docs/STORE_CHECKLIST.md`](docs/STORE_CHECKLIST.md) - что нужно для публикации в магазины
- [`docs/RELEASE_STATUS.md`](docs/RELEASE_STATUS.md) - что уже сделано и что осталось
- [`docs/IOS_PUSH_SETUP.md`](docs/IOS_PUSH_SETUP.md), [`docs/RUSTORE_PUSH.md`](docs/RUSTORE_PUSH.md) - настройка push
- [`docs/CHATBOT_GUIDE.md`](docs/CHATBOT_GUIDE.md) - сценарий чат-бота
- [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) - политика конфиденциальности
