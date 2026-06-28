# Приложение «ЛК Интерра» (Flutter)

WebView-обёртка над `stat.interra.ru` с авто-логином в UTM5, защищённым
хранением учётных данных и push-уведомлениями (FCM).

> Перед началом установите окружение: [`../docs/INSTALL_FLUTTER.md`](../docs/INSTALL_FLUTTER.md).

В репозитории лежат только `lib/` и `pubspec.yaml` — платформенные папки
(`android/`, `ios/`) генерируются командой `flutter create` локально.

## Шаги настройки

### 1. Сгенерировать платформенные папки

```bash
cd app
flutter create --org ru.interra --project-name lk_interra .
```

> `flutter create` может перезаписать `pubspec.yaml` и `lib/main.dart` своими
> шаблонами. Сразу верните наши версии:
> ```bash
> git checkout -- pubspec.yaml lib/main.dart
> ```

### 2. Установить зависимости

```bash
flutter pub get
```

### 3. Подключить Firebase (для push)

Самый простой путь — FlutterFire CLI:

```bash
dart pub global activate flutterfire_cli
flutterfire configure
```

Команда создаст `lib/firebase_options.dart`, `android/app/google-services.json`
и (для iOS) `GoogleService-Info.plist`, привязав приложение к вашему
Firebase-проекту. Используйте **тот же проект**, что и бэкенд (`server/`).

> Если используете `flutterfire configure`, замените в `lib/main.dart`
> `Firebase.initializeApp()` на
> `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)`
> и добавьте `import 'firebase_options.dart';`.

### 4. Указать адрес бэкенда

В `lib/config.dart` поле `backendBaseUrl` — поставьте реальный домен сервера.
Для отладки на эмуляторе Android локальный сервер доступен по `http://10.0.2.2:8080`.

### 5. Android: разрешения

В `android/app/src/main/AndroidManifest.xml` добавьте (если нет):

```xml
<uses-permission android:name="android.permission.INTERNET"/>
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
```

Минимальный `minSdkVersion` — 21 (требование firebase_messaging / webview).

### 6. Запуск

```bash
flutter devices         # убедиться, что телефон/эмулятор виден
flutter run             # запуск в режиме отладки
flutter build apk --release   # сборка APK
```

## Как это работает

| Файл                          | Назначение                                              |
|-------------------------------|---------------------------------------------------------|
| `lib/main.dart`               | Инициализация Firebase/push, выбор экрана по наличию логина |
| `lib/screens/login_screen.dart`   | Ввод и сохранение логина/пароля                     |
| `lib/screens/webview_screen.dart` | WebView + авто-логин (подстановка `user`/`pass`)    |
| `lib/screens/settings_screen.dart`| Уведомления, выход из аккаунта                       |
| `lib/services/auth_store.dart`    | Защищённое хранилище учётных данных                  |
| `lib/services/push_service.dart`  | FCM: токен, разрешения, показ уведомлений            |
| `lib/services/api_client.dart`    | Регистрация устройства на бэкенде                    |

Авто-логин использует реальные имена полей формы UTM5: `user` (логин) и
`pass` (пароль) на странице `…/cgi-bin/utm5/aaa`.
