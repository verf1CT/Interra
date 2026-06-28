# Сборка iOS-версии на Mac

iOS-папка (`app/ios/`) уже сгенерирована, Dart-код общий с Android — отдельное
приложение писать не нужно. Ниже — что сделать на Mac, чтобы собрать и запустить
на iPhone. **Всё это выполняется только на macOS (требование Apple).**

## 1. Поставить инструменты

```bash
# Xcode — из App Store, затем:
sudo xcodebuild -license accept
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer

# CocoaPods
sudo gem install cocoapods    # или: brew install cocoapods

# Flutter (если ещё нет)
brew install --cask flutter
flutter doctor                # добиться зелёных галочек для Xcode
```

## 2. Получить проект и зависимости

```bash
git clone <адрес-репозитория> interra
cd interra/app
flutter pub get
```

> Кириллица в пути на macOS не мешает сборке (проблема была только на Windows),
> так что класть проект можно куда угодно.

## 3. Firebase для iOS — уже почти готово

iOS-приложение **уже зарегистрировано** в Firebase-проекте `interra-5a99e`
(bundle id `ru.interra.lkInterra`), а файл `ios/Runner/GoogleService-Info.plist`
**уже лежит в репозитории**. Нужно только подключить его к Xcode-проекту:

- Открыть `ios/Runner.xcworkspace` в Xcode (шаг 4),
- перетащить `Runner/GoogleService-Info.plist` в группу **Runner** в дереве слева,
- в диалоге снять «Copy items if needed» (файл уже на месте), отметить target **Runner**.

> Альтернатива: `dart pub global activate flutterfire_cli && flutterfire configure`
> — подхватит существующее iOS-приложение и пропишет всё само (нужен вход в Firebase CLI).

## 4. Подпись и Bundle ID (Xcode)

```bash
open ios/Runner.xcworkspace
```

В Xcode → **Runner → Signing & Capabilities**:
- **Team** — выбрать ваш Apple ID / Apple Developer Team.
  - Для запуска на своём iPhone хватает бесплатного Apple ID.
  - Для App Store и стабильного push нужен платный **Apple Developer ($99/год)**.
- **Bundle Identifier** — `ru.interra.lkInterra` (или свой; тогда тот же id указать в Firebase).

## 5. Включить push-возможности

В том же разделе **Signing & Capabilities** нажать **+ Capability** и добавить:
- **Push Notifications**
- **Background Modes** → отметить *Remote notifications*
  (в `Info.plist` фоновый режим уже прописан, capability добавит entitlement `aps-environment`).

## 6. APNs-ключ в Firebase (чтобы push доходил на iPhone)

1. Apple Developer → **Keys** → создать **APNs Auth Key** (.p8), запомнить Key ID и Team ID.
2. Firebase Console → Project settings → **Cloud Messaging** → раздел *Apple app configuration* → загрузить `.p8`, указать Key ID и Team ID.

Без этого пуши на iOS приходить не будут (на Android работают и так).

## 7. Запуск и сборка

```bash
flutter devices                       # подключённый iPhone должен быть виден
flutter run                           # запуск на устройстве
flutter build ipa                     # релизная сборка (.ipa в build/ios/ipa)
```

Первый запуск на iPhone: на телефоне в **Настройки → Основные → VPN и управление
устройством** доверить ваш сертификат разработчика.

## Что уже сделано в репозитории
- `ios/` сгенерирован, `Info.plist`: имя «ЛК Интерра», фоновый режим push.
- Dart-код (WebView, авто-логин, push, экраны) общий — менять под iOS не нужно.
- Осталось только то, что требует Mac/Apple-аккаунт: шаги 3–6 выше.
