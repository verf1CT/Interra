# iOS push (APNs) — активация после оплаты Apple Developer

Пока аккаунт ($99/год) не активен, push на iOS работать не может (нужен платный
App ID с Push-капабилити и APNs-ключ в Firebase). Всё, что можно подготовить
заранее, уже лежит в репозитории — ниже шаги, чтобы включить push за ~15 минут,
когда подписка активируется.

> Файл `app/ios/Runner/Runner.entitlements` уже создан, но **намеренно не подключён**
> к подписи — иначе текущая сборка на free-provisioning перестанет ставиться.

## 1. В Apple Developer (developer.apple.com)
1. **Certificates, Identifiers & Profiles → Identifiers** → App ID `ru.interra.lkInterra`.
2. Включить **Push Notifications**.
3. **Keys → +** → создать **APNs Auth Key** (.p8). Сохранить файл, **Key ID** и **Team ID**.

## 2. В Firebase Console (проект уже подключён, конфиги в репо)
1. **Project Settings → Cloud Messaging → Apple app configuration**.
2. Загрузить **APNs Auth Key (.p8)** + Key ID + Team ID.

## 3. В Xcode (open `app/ios/Runner.xcworkspace`)
1. Target **Runner → Signing & Capabilities**.
2. **+ Capability → Push Notifications** (Xcode сам пропишет entitlement).
3. **+ Capability → Background Modes** → отметить **Remote notifications**
   (в `Info.plist` уже есть `remote-notification`/`fetch`, шаг продублирует это в UI).
4. Убедиться, что **Automatically manage signing** включён и выбран платный Team.

> Если предпочитаете не трогать UI: задать в проекте
> `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` для Debug и Release.

## 4. Проверка
1. `cd app && flutter run --release -d <device>` — приложение запросит разрешение на
   уведомления (`PushService.init()` уже это делает).
2. В логах должен появиться FCM-токен (`registerCurrentToken`), устройство
   зарегистрируется на нашем бэкенде (`server`, `POST /api/devices/register`).
3. Тестовая рассылка через бэкенд: `server/src/routes/admin.js` → проверить доставку.

## Перед релизом
- Для App Store сменить `aps-environment` на `production` (Xcode делает это
  автоматически для Release-сборки при правильном профиле).
- Проверить, что APNs-ключ в Firebase — один на Debug и Production (так и есть для .p8).
