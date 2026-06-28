# Установка окружения для сборки приложения (Windows)

Нужно один раз поставить Flutter SDK + Android-инструменты. iOS-версию можно
собрать только на macOS, поэтому ниже — про Android (он же даёт основную аудиторию).

## Вариант А — быстро, через winget (рекомендуется)

Откройте PowerShell и выполните:

```powershell
winget install --id Google.Flutter -e        # Flutter SDK (включает Dart)
winget install --id Google.AndroidStudio -e   # Android Studio + Android SDK
```

> Если `winget install Google.Flutter` не находит пакет — используйте Вариант Б.

После установки **перезапустите терминал** и проверьте:

```powershell
flutter --version
```

## Вариант Б — вручную

1. Скачайте Flutter SDK: https://docs.flutter.dev/get-started/install/windows
   Распакуйте, например, в `C:\src\flutter`.
2. Добавьте `C:\src\flutter\bin` в переменную среды `PATH`.
3. Установите Android Studio: https://developer.android.com/studio
   При первом запуске мастер скачает Android SDK, platform-tools, emulator.

## Завершение настройки (оба варианта)

```powershell
# Принять лицензии Android SDK
flutter doctor --android-licenses

# Проверить, что всё на месте
flutter doctor
```

Добивайтесь, чтобы в `flutter doctor` были зелёные галочки у:
- ✓ Flutter
- ✓ Android toolchain
- ✓ Android Studio

(Пункты про Visual Studio / Chrome / VS Code не обязательны для сборки APK.)

## Устройство для запуска

- **Реальный телефон**: включите «Параметры разработчика» → «Отладка по USB»,
  подключите кабелем. Проверка: `flutter devices`.
- **Эмулятор**: Android Studio → Device Manager → создать виртуальное устройство.

## Что дальше

После `flutter doctor` без критичных ошибок — переходите к
[`app/README.md`](../app/README.md): там команды для генерации платформенных
папок и запуска приложения.
