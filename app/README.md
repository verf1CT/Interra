# Приложение «ЛК Интерра» (Flutter)

Личный кабинет абонента: кабинет UTM5 в WebView + нативные баланс, уведомления,
безопасность и платформенные фишки iOS/Android. Единая светлая тема в фирменных
цветах Интерры (синий `#3C98D4`, оранжевый `#F4752D`).

## Суть

Приложение авторизуется в биллинге по номеру телефона и SMS-коду (CGI `bbb`
UTM5), хранит выданный токен в защищённом хранилище и по нему при каждом запуске
получает свежую ссылку на кабинет. Кабинет рендерится в WebView, а баланс и
номер лицевого счёта вычитываются со страницы и показываются нативно.

## Структура `lib/`

| Путь | Назначение |
|------|------------|
| `main.dart` | Точка входа: UI показывается сразу, Firebase/телеметрия/push поднимаются в фоне (чтобы не блокировать первый кадр) |
| `config.dart` | Адреса биллинга/бэкенда, контакты поддержки, версия |
| `theme.dart` | Фирменная палитра и тема Material 3 |
| `screens/register_screen.dart` | Вход: телефон → SMS-код (антиспам-кулдаун, автоподстановка кода) |
| `screens/webview_screen.dart` | Кабинет в WebView: авто-получение ссылки, офлайн-кэш, pull-to-refresh, чип баланса |
| `screens/settings_screen.dart` | Аккаунт, категории уведомлений, безопасность, задержка автоблокировки |
| `screens/support_screen.dart` | Связь с провайдером, диагностика, проверка скорости |
| `screens/diagnostics_screen.dart` | Пошаговая диагностика сети с вердиктом |
| `screens/speedtest_screen.dart` | Замер скорости (пинг/загрузка/отдача) |
| `screens/biometric_gate.dart`, `pin_setup_screen.dart` | Замок: Face ID/отпечаток и код-пароль |
| `services/` | Логика без UI (см. ниже) |
| `widgets/` | `privacy_shield` (заслонка в переключателе задач), `cabinet_skeleton`, `pin_pad` |
| `utils/phone.dart` | Нормализация и форматирование телефона (покрыто тестами) |

### Ключевые сервисы (`lib/services/`)

- `billing_api.dart` — штатный API UTM5 `bbb` (регистрация по SMS, ссылка на кабинет).
- `secure_http.dart` — HTTP-клиент с **пиннингом** корней Let's Encrypt для запросов к биллингу/бэкенду.
- `auth_store.dart` — токен и телефон в Keychain / EncryptedSharedPreferences.
- `balance_store.dart` — распарсенный баланс: кэш, форматирование, отдача в виджеты/часы.
- `push_service.dart`, `notify_prefs.dart`, `api_client.dart` — FCM, категории уведомлений, регистрация устройства на бэкенде.
- `biometric.dart`, `pin_lock.dart` — биометрия с настраиваемой задержкой и код-пароль (хеш+соль, антиперебор).
- `net_diagnostics.dart`, `speed_test.dart`, `speed_live_activity.dart` — диагностика, спидтест и его Live Activity.
- `analytics.dart` — Firebase Analytics/Crashlytics (лениво, чтобы не ронять первый кадр).
- `quick_actions_service.dart`, `update_check.dart`, `page_cache.dart` — быстрые действия, проверка новой версии, офлайн-снимок кабинета.

## Нативные части `ios/`

- **Runner** (приложение): `AppDelegate` (мост к часам, фоновое обновление `BGTaskScheduler`, регистрация фраз Siri), `BalanceIntents.swift` (интент Siri «баланс»), `WatchSync.swift`, `LiveActivityBridge.swift`.
- **Shared/** — общий Swift для приложения и расширений: `BalanceCore.swift` (нативный запрос баланса), `SpeedActivityAttributes.swift`.
- **BalanceWidget/** (расширение): виджеты домашнего и экрана блокировки, кнопка в Пункте управления (настраиваемые через App Intents) и Live Activity спидтеста.
- **InterraWatch/** — приложение для Apple Watch (баланс на запястье, данные через WatchConnectivity).

## Нативные части `android/`

- `BalanceWidgetProvider.kt` — виджет баланса на домашнем экране.
- `BalanceTileService.kt` — плитка «Быстрых настроек» с балансом.
- `res/xml/shortcuts.xml` — ярлык «Проверить баланс» (long-press иконки).

## Данные, которыми делятся нативные части

Приложение пишет баланс, номер счёта и токен в общий контейнер (iOS — App Group
`group.ru.interra.lkInterra`, Android — `HomeWidgetPreferences`), откуда их
читают виджеты, плитка, Siri и часы.
