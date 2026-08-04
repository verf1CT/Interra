# Changelog

Все заметные изменения в проекте задокументированы в этом файле.

Формат основан на [Keep a Changelog](https://keepachangelog.com/ru/1.1.0/),
проект придерживается [Semantic Versioning](https://semver.org/lang/ru/).

## [Unreleased]

### Added

- **Watchdog Alerting**: Фоновый мониторинг здоровья системы (`watchdogService`) — авто-алерты в Telegram при потере связи с SQLite, превышении порога RAM (>450 MB) и необработанных исключениях (`uncaughtException`, `unhandledRejection`).
- **Telegram Bot**: Команда `/wizard` (или кнопка `🧙‍♂️ Пошаговая рассылка`) — пошаговый мастер создания рассылок (Заголовок → Текст → Выбор Deep Link → Предпросмотр → Подтверждение отправки кнопкой).
- **Telegram Bot**: Интерактивное меню быстрых команд (Reply Keyboard) — кнопки `🧙‍♂️ Пошаговая рассылка`, `📊 Статистика`, `💾 Бэкап БД`, `🏓 Пинг`, `❓ Справка` в нижней части экрана.
- **Telegram Bot**: Команда `/send <логин> <текст>` — отправка персонального push-уведомления конкретному абоненту.
- **Telegram Bot**: Команда `/find <логин/телефон>` — поиск устройства в базе данных по номеру или логину.
- **Telegram Bot**: Команда `/stats` — мгновенная сводка по устройствам, uptime, RAM и размеру SQLite.
- **Telegram Bot**: Команда `/backup` — отправка архива базы данных `interra.sqlite` прямо в Telegram-чат.
- **Telegram Bot**: Команда `/ping` — проверка отклика SQLite и отображение uptime/RAM.
- **Telegram Bot**: Авторизация по `chat_id` — бот принимает команды только из авторизованной группы.
- **Telegram Bot**: Встроенное меню команд (`/setMyCommands`) — список при вводе `/` в Telegram.
- **Telegram Bot**: Inline Keyboard кнопки (Админка, Документация, Метрики, Health) под сообщением о старте сервера.
- **Watchdog / Health Monitoring**: Автоматический мониторинг состояния БД SQLite, потребления памяти RAM и перехват необработанных исключений Node.js (`uncaughtException`, `unhandledRejection`) с немедленной отправкой тревожных алертов `🚨 CRITICAL` / `⚠️ WARNING` в Telegram-чат админов.
- **Deep Links**: Поддержка `screen` в push data-payload — тап по push открывает конкретный экран приложения (`diagnostics`, `settings`, `support`, `payment`, `notifications`).
- **Deep Links**: Флаг `--screen=xxx` в Telegram-команде `/push` — рассылка с автоматическим deep link.
- **Flutter**: Экран «История уведомлений» — хранение полученных push-сообщений на устройстве.
- **Flutter**: `NotificationsStore` — сервис локального хранения истории уведомлений (SharedPreferences, до 50 записей).
- **Backend**: Scalar UI интерактивная REST API документация на `/docs` и OpenAPI 3.1 спецификация на `/openapi.json`.
- **Backend**: Prometheus метрики на `/metrics` (http_request_duration_seconds).
- **Backend**: Telegram-алерты при запуске, остановке сервера и 500-ошибках.
- **Backend**: Отображение типа окружения (Localhost / Production) и полных кликабельных ссылок в Telegram-алертах.
- **CI**: GitHub Actions visual summary ($GITHUB_STEP_SUMMARY) — красивые карточки результатов в GitHub Actions.
- **CI**: Автоматическая генерация `RELEASE_NOTES.md` по Conventional Commits для GitHub Releases.
- **DX**: Интерактивный корневой `Makefile` с цветным меню (`make`, `make dev-server`, `make test`, `make build-apk` и др.).
- **DX**: ASCII-арт баннер при запуске сервера в терминале.
- **DX**: DevTools Console баннер (styled `console.log`) в `admin.html`.
- **E2E**: Интеграционный тест полного цикла рассылки (register → broadcast → verify DB → opened → unregister).

### Changed

- **Backend**: Миграция `server/` с JavaScript на TypeScript (`"strict": true`) с Zod-валидацией, Pino-логированием и Vitest-тестами.
- **Flutter**: Рефакторинг `webview_screen.dart` — декомпозиция JS interop (`CabinetInterop`) и навигации (`CabinetNavigation`), сокращение с ~740 до ~300 строк.

### Fixed

- **CI**: Исправлена ошибка `unused_import` (`url_launcher.dart`) в `flutter analyze`.
- **Backend**: Исправлен белый экран `/docs` — используется `spec: { url: '/openapi.json' }` вместо inline spec.
- **Backend**: Добавлен редирект `/` → `/admin.html` для корректной работы корня сервера.
- **Telegram**: Использование `127.0.0.1` вместо `localhost` для корректной кликабельности локальных ссылок в Telegram.

## [0.2.0] - 2026-08-03

### Added

- TypeScript backend с Clean Architecture (controllers → services → repositories).
- Zod-схемы валидации всех входных данных.
- Pino-логирование с `x-request-id` трассировкой.
- Helmet + RateLimiter для безопасности.
- Vitest интеграционные тесты (10 тестов).
- Health checks `/healthz` и `/readyz`.
- Shields.io бейджи в README.md.

## [0.1.0] - 2026-07-15

### Added

- Flutter-приложение «ЛК Интерра» с WebView-кабинетом.
- Авторизация по номеру телефона.
- FCM push-уведомления.
- Биометрический замок (Face ID / Touch ID).
- Сетевая диагностика (пинг, DNS, проверка серверов).
- Express.js backend для рассылки push-уведомлений.
