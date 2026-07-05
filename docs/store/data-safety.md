# Data Safety / Конфиденциальность — ответы для анкет магазинов

> Составлено по факту из кода приложения (на 2026-07-06). Черновик, не закоммичено.
> Для Google Play Data Safety, Apple App Privacy и раздела конфиденциальности RuStore.

## Что приложение реально собирает (из кода)

| Данные | Что именно | Куда идёт | Зачем |
|---|---|---|---|
| Номер телефона | логин абонента | наш бекенд (push.interra.ru) + Firebase Analytics (как user id) | привязка push к абоненту, аналитика |
| Push-токен (FCM) | идентификатор устройства для доставки уведомлений | наш бекенд + Firebase Cloud Messaging | отправка уведомлений |
| Платформа и версия приложения | android/ios, версия | наш бекенд | сегментация рассылок |
| События использования | открытия экранов, запуск диагностики, обращение в поддержку, быстрые действия | Firebase Analytics (Google) | улучшение приложения |
| Отчёты о сбоях | стектрейсы падений | Firebase Crashlytics (Google) | стабильность |

Хранится **локально на устройстве** (не «сбор»): токен сессии и номер телефона — в защищённом хранилище (Keychain/Keystore).

**НЕ собирается:** точная/приблизительная геолокация, контакты, фото, микрофон, камера, платёжные данные (оплата — через внешний веб-кабинет провайдера). Сканирование устройств в локальной сети остаётся на устройстве, наружу уходит только количество.

---

## Google Play — Data Safety (как отвечать)

**Does your app collect or share user data?** — Yes.

**Собираемые типы данных:**
- **Personal info → Phone number** — Collected. Shared: No*. Purpose: App functionality, Analytics. Linked to user: Yes.
- **Device or other IDs** (FCM-токен) — Collected. Shared: No*. Purpose: App functionality (push). Linked to user: Yes.
- **App activity → App interactions** — Collected. Purpose: Analytics. Linked to user: Yes.
- **App info and performance → Crash logs, Diagnostics** — Collected. Purpose: Analytics / App functionality. Linked to user: Yes/No по вкусу (Crashlytics можно как не linked).

\* «Shared» = передача третьим лицам. Firebase — это обработчик по поручению (processor), для Google Play это **не** «sharing». Данные на свой бекенд — тоже не sharing.

**Security practices:**
- Данные шифруются при передаче (HTTPS) — Yes.
- Пользователь может запросить удаление данных — Yes (укажите способ: через поддержку / отвязка устройства).

---

## Apple App Privacy (Nutrition Labels)

- **Identifiers → Phone Number / User ID** — Used for: App Functionality, Analytics. Linked to user: Yes.
- **Identifiers → Device ID** (push token) — App Functionality. Linked: Yes.
- **Usage Data → Product Interaction** — Analytics. Linked: Yes.
- **Diagnostics → Crash Data, Performance Data** — App Functionality/Analytics. Linked: можно No.
- Tracking (кросс-приложение/рекламное отслеживание) — **No** (ATT не требуется, рекламных SDK нет).

---

## Важно перед подачей

- В политике конфиденциальности перечислить те же данные и Firebase как обработчика.
- Указать способ удаления данных (для Google требуется URL или инструкция).
- Проверить: если добавите RuStore Push SDK — там свой идентификатор устройства, дописать в анкеты.
