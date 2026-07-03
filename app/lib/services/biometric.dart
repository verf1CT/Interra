import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// биометрический вход (Face ID / Touch ID / отпечаток).
///
/// Опционален: включается пользователем в настройках. если устройство не
/// поддерживает биометрию - переключатель недоступен, а гейт пропускается
class Biometric {
  static final _auth = LocalAuthentication();
  static const _kEnabled = 'biometric_enabled';
  static const _kLastUnlock = 'lock_last_unlock_ms';
  static const _kLockDelay = 'lock_delay_ms';

  /// спецзначение задержки: «никогда» - после первой разблокировки больше не
  /// спрашиваем (но первый вход в приложении всё равно под замком)
  static const int lockDelayNever = -1;

  /// значение по умолчанию - 30 минут. баланс - данные личные, но не
  /// банковские; спрашивать при каждом переключении приложений назойливо
  static const int defaultLockDelayMs = 30 * 60 * 1000;

  /// варианты для настроек: (значение в мс, подпись)
  static const List<(int, String)> lockDelayOptions = [
    (0, 'Сразу'),
    (60 * 1000, 'Через 1 минуту'),
    (defaultLockDelayMs, 'Через 30 минут'),
    (lockDelayNever, 'Никогда'),
  ];

  static Future<int> get lockDelayMs async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_kLockDelay) ?? defaultLockDelayMs;
  }

  static Future<void> setLockDelayMs(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLockDelay, value);
  }

  static String lockDelayLabel(int ms) => lockDelayOptions
      .firstWhere((o) => o.$1 == ms, orElse: () => lockDelayOptions[2])
      .$2;

  /// отмечает успешную разблокировку (биометрией или PIN) - от этого момента
  /// отсчитывается льготный период
  static Future<void> markUnlocked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kLastUnlock, DateTime.now().millisecondsSinceEpoch);
  }

  /// true - льготный период ещё действует, замок можно не показывать
  static Future<bool> get withinGracePeriod async {
    final delay = await lockDelayMs;
    if (delay == 0) return false; // всегда спрашивать
    final prefs = await SharedPreferences.getInstance();
    final last = prefs.getInt(_kLastUnlock);
    // ни разу не разблокировали - замок нужен (даже при «никогда»)
    if (last == null) return false;
    if (delay == lockDelayNever) return true; // дальше уже не перезапрашиваем
    final elapsed = DateTime.now().millisecondsSinceEpoch - last;
    // отрицательное elapsed (перевод часов назад) считаем истёкшим
    return elapsed >= 0 && elapsed < delay;
  }

  /// доступна ли биометрия на устройстве
  static Future<bool> get isAvailable async {
    try {
      return (await _auth.isDeviceSupported()) &&
          (await _auth.canCheckBiometrics);
    } catch (e) {
      debugPrint('Biometric.isAvailable: $e');
      return false;
    }
  }

  static Future<bool> get isEnabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kEnabled) ?? false;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kEnabled, value);
  }

  /// запрашивает подтверждение. true - успех или биометрия не требуется
  static Future<bool> authenticate() async {
    try {
      return await _auth.authenticate(
        localizedReason: 'Подтвердите вход в личный кабинет',
        biometricOnly: false, // допускаем код-пароль как запасной вариант
        persistAcrossBackgrounding: true, // бывший stickyAuth
      );
    } catch (e) {
      debugPrint('Biometric.authenticate: $e');
      return false;
    }
  }
}
