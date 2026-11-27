# ЛК Интерра

[![CI](https://github.com/verf1CT/Interra/actions/workflows/ci.yml/badge.svg)](https://github.com/verf1CT/Interra/actions)

Мобильный личный кабинет для абонентов [Интерры](https://interra.ru), это провайдер в Первоуральске. Приложение под iOS и Android, к нему небольшой сервер для пушей и бота поддержки.

В приложении видно баланс, тариф и когда следующее списание. Пополнить можно сразу на странице банка, без захода на сайт. Есть история операций по месяцам, услуги, пакеты Смотрёшки и IPTV с подключением, смена тарифа и диагностика сети. Если денег не хватает на списание, за три дня приходит напоминание. Если на номере несколько лицевых счетов, между ними можно переключаться.

## Что где лежит

| Папка | Что внутри |
|-------|-----------|
| `app/` | само приложение на Flutter |
| `server/` | Node.js: пуш-рассылки, админка, бот для Telegram и MAX |
| `deploy/` | nginx и systemd для боевого сервера |
| `docs/` | чеклисты для магазинов, настройка пушей, политика конфиденциальности |

## Откуда приложение берёт данные

Всё про счёт приложение берёт прямо из биллинга UTM5 на `stat.interra.ru`, наш сервер тут вообще ни при чём. API у UTM5 нет, так что приложение качает страницы кабинета и разбирает HTML (`app/lib/services/cabinet_parser.dart`). Это самое хрупкое место: поменяет Интерра вёрстку - у всех пропадёт баланс. Поэтому парсеры сделаны чистыми функциями от строки HTML и проверяются тестами на кусках настоящих страниц.

С нашим сервером на `push.interra.ru` приложение общается один раз, когда регистрирует токен для пушей. Дальше сервер сам шлёт рассылки через Firebase Cloud Messaging - из админки, из бота или по расписанию.

## Приложение

Flutter 3.44, точная версия зафиксирована в CI.

```bash
cd app
flutter pub get
flutter run
flutter analyze lib test
flutter test
```

Релизы собирает CI. Локальный `flutter build apk --release` без своего keystore не соберётся.

На Windows `flutter analyze` падает с `FormatException`, если в пути к проекту есть кириллица. Я обхожу так: `subst I: "<путь к репозиторию>"` и анализ из `I:\app`.

Для скриншотов в магазины и для модераторов есть демо-режим с выдуманным абонентом, в релизе он выключен. Скриншоты всех экранов в обеих темах снимает `SHOTS_DIR=<папка> flutter test tool/shots.dart`.

Когда биллинг что-то меняет, нужны живые страницы кабинета. Для этого на компе запускается `dart tool/dump_server.dart`, а в приложении долгое нажатие на плашку лицевого счёта отправляет на него дамп. Токены сессии в дампе замаскированы.

## Сервер

Node.js 18 или новее.

```bash
cd server
cp .env.example .env     # ADMIN_TOKEN, ключ Firebase, токены ботов
npm install
npm run dev              # с перезапуском при изменениях
npm test                 # Vitest, база в памяти
```

| Команда | Что делает |
|---------|-----------|
| `npm start` | обычный запуск |
| `npm run bot` | Telegram-бот отдельным процессом |
| `npm run bot:max` | бот для MAX |
| `npm run bot:sim` | поговорить с ботом в консоли |
| `npm run build-ui` | собрать админку из `admin-ui/` в `server/public` |

Без `ADMIN_TOKEN` админка никого не пустит. `.env` и `serviceAccountKey.json` в git не попадают. Как разворачивать, написано в [`docs/DEPLOY.md`](docs/DEPLOY.md) и [`server/ADMIN.md`](server/ADMIN.md).

## CI и релизы

На каждый пуш в `main` GitHub Actions гоняет анализ и тесты Flutter и тесты сервера. Потом собирает подписанные APK и AAB, IPA без подписи и выкладывает всё релизом с тегом `build-<номер>`. IPA ставлю на телефон через Sideloadly или AltStore. Из тех же файлов приложение уходит в Google Play, RuStore и App Store.

## Документы

- [`docs/STORE_CHECKLIST.md`](docs/STORE_CHECKLIST.md) и [`docs/APP_STORE_READINESS.md`](docs/APP_STORE_READINESS.md) - что нужно для публикации
- [`docs/RELEASE_STATUS.md`](docs/RELEASE_STATUS.md) - что уже сделано и что осталось
- [`docs/IOS_PUSH_SETUP.md`](docs/IOS_PUSH_SETUP.md), [`docs/RUSTORE_PUSH.md`](docs/RUSTORE_PUSH.md) - пуши
- [`docs/INSTALL_FLUTTER.md`](docs/INSTALL_FLUTTER.md), [`docs/INSTALL_MACOS_IOS.md`](docs/INSTALL_MACOS_IOS.md) - как поставить окружение
- [`docs/CHATBOT_GUIDE.md`](docs/CHATBOT_GUIDE.md) - сценарий бота
- [`docs/PRIVACY_POLICY.md`](docs/PRIVACY_POLICY.md) - политика конфиденциальности
