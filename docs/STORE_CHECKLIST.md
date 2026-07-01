# Чеклист публикации в сторы (Google Play / RuStore)

Состояние на 2 июля 2026. Что уже готово в репозитории и что осталось.

## Уже готово

- [x] Версия **1.0.0+2** (`app/pubspec.yaml`), в UI — `AppConfig.appVersion`.
- [x] **Release-подпись Android**: ключ `app/android/upload-keystore.p12` +
      `app/android/key.properties` (оба в .gitignore, в репозиторий не попадают).
      Сборка: `flutter build appbundle` → подписанный `.aab` для Play,
      `flutter build apk` → подписанный `.apk` для RuStore.
      ⚠️ **Сделать резервную копию ключа и key.properties** — при утере ключа
      обновлять приложение в сторах будет нельзя.
- [x] Имя приложения: **«ЛК Интерра»** (не конфликтует с занятым «Interra»).
- [x] `applicationId`: `ru.interra.lk_interra`.
- [x] Политика конфиденциальности: `docs/PRIVACY_POLICY.md` — **нужно
      захостить** (например, страница на interra.ru или GitHub Pages) и
      указать URL в консолях сторов.

## Осталось сделать

### Общее
- [ ] Захостить политику конфиденциальности, получить публичный URL.
- [ ] Скриншоты: телефон 6.5" (минимум 2–4 шт.), можно с обоих iPhone/эмулятора.
- [ ] Короткое (до 80 зн.) и полное (до 4000 зн.) описание приложения.
- [ ] Иконка 512×512 (есть `app/assets/icon_full.png` — проверить размер).

### Google Play (ждём ответ админов про аккаунт)
- [ ] Аккаунт разработчика ($25 разово). Выяснить, кто занял имя «Interra».
- [ ] `flutter build appbundle --release` → загрузить `.aab`.
- [ ] Анкета Data safety: собираем телефон (регистрация), FCM-токен,
      Analytics/Crashlytics — без продажи данных.
- [ ] Для рассылки Java/JDK на этом маке нет — для сборки Android поставить:
      `brew install --cask temurin` + Android SDK, либо собирать в CI.

### RuStore (ждём аккаунт от админов на юрлицо)
- [ ] Аккаунт разработчика на ООО «Интерра» (бесплатно, нужна УКЭП).
- [ ] `flutter build apk --release` → загрузить `.apk`.
- [ ] Push через FCM в RuStore-сборке работает, если на устройстве есть
      сервисы Google; для полного покрытия позже можно добавить RuStore Push SDK.

### App Store (после платного Apple Developer)
- [ ] Аккаунт $99/год (написано админам).
- [ ] Включить Push capability + APNs-ключ (см. `docs/IOS_PUSH_SETUP.md`).
- [ ] `aps-environment` → production, сборка через Xcode Organizer / Transporter.
